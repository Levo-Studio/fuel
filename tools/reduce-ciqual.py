#!/usr/bin/env python3
"""Reduce the ANSES-CIQUAL food composition table to the file Fuel ships.

CIQUAL publishes 3,185 foods with 67 constituents each, as five XML files
totalling about 100 MB uncompressed. Fuel needs four numbers per food and a
name to search on, so almost all of that is dropped here rather than carried
onto a phone.

Usage:

    python3 tools/reduce-ciqual.py <ciqual-xml-dir> <output.fueltable>

where <ciqual-xml-dir> holds the unpacked contents of the CIQUAL XML archive
(alim_*.xml, compo_*.xml, const_*.xml). The archive is not committed: it is
11.4 MB of source data for a 300 KB artefact, and the URL and release are
recorded next to the output instead.

The script is deterministic. The same input directory produces the same bytes,
so a reviewer can re-run it and diff.
"""

import os
import re
import struct
import sys
import unicodedata

# MARK: - CIQUAL constituent codes
#
# 328 is energy under EU Regulation 1169/2011, which is the same calculation a
# packaged food's label uses. CIQUAL also carries 333 (N x Jones' factor, with
# fibres), which is a different and slightly higher number for the same food.
# Fuel takes 328 because the user's mental model of a calorie comes from
# labels, and a tracker that disagrees with the packet is a tracker nobody
# trusts.
ENERGY_KCAL = "328"
PROTEIN = "25000"
CARBOHYDRATE = "31000"
FAT = "40000"
WATER = "400"

# MARK: - Preparation state
#
# CIQUAL has no column saying whether a row is the raw food or the cooked one.
# The distinction exists only in the two names, and the obvious rule — look for
# "raw", look for "cooked" — gets the food that motivated this whole feature
# exactly backwards:
#
#     9614  Polenta or Maize/corn semolina, pre-cooked, dried
#     9615  Polenta or maize semolina, cooked, unsalted
#
# The raw row contains "cooked" (inside "pre-cooked") and does not contain
# "raw". "Lentil, dried" and "Lentil, boiled/cooked in water" are the same
# shape without the trap. So the rule below works on the comma-separated
# qualifiers rather than on the whole string, reads French and English
# together, and strikes "pre-cooked" out before anything looks for "cooked" —
# "pre-cooked" describes how the product was manufactured, not the state it is
# in on the shelf.
#
# The state is computed here, at build time, and stored as a field. The device
# reads a byte and does no guessing, a wrong classification is fixable in one
# place, and the classification is reviewable as data rather than as behaviour.

NEUTRALISED = [
    # Struck out before either vocabulary is consulted. Each of these contains
    # a cooking word and does not describe a cooked food.
    "pre-cooked", "precooked", "precuite", "precuit", "pre-cuit",
    "half-cooked", "to be cooked", "a cuire", "uncooked", "non cuit",
]

RAW_TERMS = [
    "raw", "cru", "crue", "crus", "crues",
    "dried", "dry", "dehydrated", "sec", "seche", "sechee", "deshydrate",
    "deshydratee", "en poudre", "powder", "powdered", "frozen",
]

COOKED_TERMS = [
    "cooked", "cuit", "cuite", "cuits", "cuites",
    "boiled", "bouilli", "bouillie", "poached", "poche", "pochee",
    "baked", "roasted", "roti", "rotie", "grilled", "grille", "grillee",
    "fried", "frit", "frite", "pan-fried", "sauteed", "saute", "sautee",
    "steamed", "vapeur", "braised", "braise", "braisee",
    "stewed", "mijote", "mijotee", "reconstituted", "reconstituee",
    "prepared", "reheated", "rechauffe", "rechauffee",
]

def fold(text):
    """Lowercase, strip accents, collapse whitespace."""
    decomposed = unicodedata.normalize("NFD", text.lower())
    stripped = "".join(c for c in decomposed if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", stripped).strip()


def preparation_state(name_en, name_fr):
    """0 unspecified, 1 raw, 2 prepared.

    CIQUAL names a food as a head followed by comma-separated qualifiers, and
    **the state is the last thing said**, because the qualifiers narrow from
    what the food is to what was done to it. Reading the whole name at once
    fails on that ordering, and it fails on the two foods this feature exists
    for:

        9810  Pasta, dry, regular, raw
        9811  Pasta, dry, regular, cooked, no added salt
        9614  Polenta or maize/corn semolina, pre-cooked, raw
        9615  Polenta or maize/corn semolina, cooked, no added salt

    "dry" in the pasta rows is the kind of pasta and not its state; both rows
    carry it and only one of them is raw. "pre-cooked" in the polenta row is
    how the grain was milled; the row is the dry one. A rule that scans the
    whole string sees "dry" and "cooked" in the same name and gives up, or
    worse, picks the first one it meets and prices raw polenta as cooked —
    which is the exact 350-versus-76 error this table replaces.

    So the qualifiers are walked from the end, and the first one carrying a
    word from either vocabulary decides. Everything before it is the food.
    Where one qualifier carries both — "dehydrated and reconstituted" — the
    word standing later wins, for the same reason the last qualifier does: the
    name is written as a sequence of things that happened.

    Both names are read, English first. They agree in almost every row, and
    where the English is thin the French carries the state anyway."""
    for name in (name_en, name_fr):
        folded = fold(name)
        for term in NEUTRALISED:
            folded = folded.replace(term, " ")

        qualifiers = folded.split(",")[1:]
        for qualifier in reversed(qualifiers):
            raw_at = last_match(qualifier, RAW_TERMS)
            cooked_at = last_match(qualifier, COOKED_TERMS)
            if raw_at is None and cooked_at is None:
                continue
            if cooked_at is None:
                return 1
            if raw_at is None:
                return 2
            return 1 if raw_at > cooked_at else 2

    return 0


def last_match(text, terms):
    """The position of the last of `terms` occurring in `text` as a whole
    word, or None. Whole-word so that "parboiled" is not "boiled" and
    "sectioned" is not "sec"."""
    best = None
    for term in terms:
        for match in re.finditer(r"(?<![a-z])%s(?![a-z])" % re.escape(term), text):
            if best is None or match.start() > best:
                best = match.start()
    return best


# MARK: - Reading CIQUAL

def read_records(path, tag):
    # The 2020 release was windows-1252 and the 2025 one is UTF-8, and cp1252
    # decodes any byte at all — so guessing wrong is silent mojibake in every
    # accented French name rather than an error. The declaration is read
    # instead of assumed.
    with open(path, "rb") as handle:
        data = handle.read()
    declared = re.search(rb'encoding="([^"]+)"', data[:200])
    encoding = declared.group(1).decode("ascii") if declared else "utf-8"
    text = data.decode(encoding).lstrip("\ufeff")
    for match in re.finditer(r"<%s>(.*?)</%s>" % (tag, tag), text, re.S):
        body = match.group(1)
        record = {}
        for field in re.finditer(r"<([A-Za-z_]+)>([^<]*)</\1>", body):
            record[field.group(1).lower()] = field.group(2).strip()
        yield record


def parse_value(raw):
    """CIQUAL writes a missing value as '-', a below-detection value as
    '< 0,01' and 'traces', and a decimal with a comma.

    '-' is genuinely unknown and disqualifies the food. 'traces' and '< x' are
    known to be near zero, and are taken as zero rather than thrown away: a
    food with trace fat is not a food with unknown fat, and dropping it would
    lose real rows for no gain."""
    if raw in ("", "-"):
        return None
    if raw == "traces":
        return 0.0
    if raw.startswith("<"):
        return 0.0
    try:
        return float(raw.replace(",", "."))
    except ValueError:
        return None


def tokenise(text):
    return [t for t in re.split(r"[^a-z0-9]+", fold(text)) if len(t) > 1]


# MARK: - Writing the artefact
#
# A memory-mapped binary rather than JSON or SQLite. JSON would have to be
# parsed in full before the first search, which is the one thing the brief
# rules out. SQLite would carry a query engine and a build-setting change for
# a table of three thousand rows that never gets written to. This is a sorted
# array and a token index: the file is mapped, nothing is decoded until it is
# read, and a search is two binary searches and a walk.
#
# Every multi-byte field is little-endian and read on the device with
# loadUnaligned, so no section needs padding to an alignment.

MAGIC = b"FTBL"
VERSION = 1
HEADER = 32
FOOD_RECORD = 28
TOKEN_RECORD = 12


def build(source_dir, output_path):
    alim = [f for f in os.listdir(source_dir) if f.startswith("alim_2")]
    compo = [f for f in os.listdir(source_dir) if f.startswith("compo_")]
    if not alim or not compo:
        raise SystemExit("expected alim_*.xml and compo_*.xml in %s" % source_dir)

    names = {}
    for record in read_records(os.path.join(source_dir, alim[0]), "ALIM"):
        names[record["alim_code"]] = (record.get("alim_nom_eng", ""), record.get("alim_nom_fr", ""))

    wanted = {ENERGY_KCAL, PROTEIN, CARBOHYDRATE, FAT, WATER}
    values = {}
    for record in read_records(os.path.join(source_dir, compo[0]), "COMPO"):
        const = record.get("const_code")
        if const not in wanted:
            continue
        values.setdefault(record["alim_code"], {})[const] = parse_value(record.get("teneur", ""))

    foods = []
    dropped = 0
    incomplete = 0
    for code, (name_en, name_fr) in sorted(names.items(), key=lambda kv: int(kv[0])):
        row = values.get(code, {})
        kcal = row.get(ENERGY_KCAL)
        protein = row.get(PROTEIN)
        carbs = row.get(CARBOHYDRATE)
        fat = row.get(FAT)
        # Energy is the one value a calorie tracker cannot do without, so a
        # food without it is dropped. A missing macro is not the same thing
        # and is **not** grounds for dropping the row: CIQUAL has no fat
        # figure for cooked polenta (9615), and an earlier version of this
        # script therefore threw away the very row this feature was written to
        # find. It is stored as NaN — the device reads it back as "CIQUAL does
        # not say", which is a different statement from "zero" and is the only
        # honest one. Filling the gap by difference would be inventing a value
        # and presenting it as ANSES's, which their terms of reuse forbid.
        if not name_en or kcal is None:
            dropped += 1
            continue
        incomplete += (protein is None or carbs is None or fat is None)
        foods.append({
            "code": int(code),
            "name": name_en,
            "name_fr": name_fr,
            "kcal": kcal,
            "protein": float("nan") if protein is None else protein,
            "carbs": float("nan") if carbs is None else carbs,
            "fat": float("nan") if fat is None else fat,
            "water": row.get(WATER),
            "state": preparation_state(name_en, name_fr),
        })

    check_states(foods)

    # Tokens come from the English name only, and only the English name.
    # Fuel is English-only end to end: the estimate contract asks both
    # providers for English field names and the app normalises the model's
    # own reply into English regardless of what language the user typed in,
    # so a search term reaching this table has never been anything but an
    # English word — "polenta", "egg", "cottage cheese" — never
    # "polenta ou semoule de mais". Indexing the French name as well used to
    # widen the vocabulary a query could hit; it was also indexing forty-six
    # hundred words nothing arriving here would ever be written in. There is
    # no language detection or fallback in the lookup itself for the same
    # reason: one language arrives, so one column is searched.
    #
    # `name_fr` is still read above, into `preparation_state`, which is a
    # different question — not what a query will say, but what CIQUAL itself
    # says about a food, and CIQUAL sometimes says the raw-versus-cooked
    # qualifier more plainly in French than in English.
    postings = {}
    for index, food in enumerate(foods):
        for token in set(tokenise(food["name"])):
            postings.setdefault(token, []).append(index)

    tokens = sorted(postings)

    names_blob = bytearray()
    name_spans = []
    for food in foods:
        encoded = food["name"].encode("utf-8")
        name_spans.append((len(names_blob), len(encoded)))
        names_blob += encoded

    token_blob = bytearray()
    token_spans = []
    for token in tokens:
        encoded = token.encode("utf-8")
        token_spans.append((len(token_blob), len(encoded)))
        token_blob += encoded

    posting_blob = bytearray()
    posting_spans = []
    for token in tokens:
        entries = postings[token]
        posting_spans.append((len(posting_blob) // 4, len(entries)))
        for index in entries:
            posting_blob += struct.pack("<I", index)

    food_section = bytearray()
    for food, (offset, length) in zip(foods, name_spans):
        food_section += struct.pack(
            "<IffffIHBB",
            food["code"], food["kcal"], food["protein"], food["carbs"], food["fat"],
            offset, length, food["state"], 0,
        )

    token_section = bytearray()
    for (offset, length), (start, count) in zip(token_spans, posting_spans):
        token_section += struct.pack("<IHIH", offset, length, start, count)

    header = struct.pack(
        "<4sIIIIIQ", MAGIC, VERSION, len(foods), len(tokens),
        len(posting_blob) // 4, len(names_blob), 0,
    )
    assert len(header) == HEADER, len(header)
    assert len(food_section) == FOOD_RECORD * len(foods)
    assert len(token_section) == TOKEN_RECORD * len(tokens)

    with open(output_path, "wb") as handle:
        handle.write(header)
        handle.write(food_section)
        handle.write(token_section)
        handle.write(posting_blob)
        handle.write(names_blob)
        handle.write(token_blob)

    raw_count = sum(1 for f in foods if f["state"] == 1)
    cooked_count = sum(1 for f in foods if f["state"] == 2)
    print("foods            %d (dropped %d without an energy value or a name)" % (len(foods), dropped))
    print("  incomplete     %d carry a gap in one or more macro" % incomplete)
    print("  raw            %d" % raw_count)
    print("  prepared       %d" % cooked_count)
    print("  unspecified    %d" % (len(foods) - raw_count - cooked_count))
    print("tokens           %d" % len(tokens))
    print("postings         %d" % (len(posting_blob) // 4))
    print("bytes            %d" % os.path.getsize(output_path))


def check_states(foods):
    """Cross-check the name-derived state against a column, as far as a column
    can check it.

    The obvious candidate is water content, and the first version of this check
    asserted that a raw row holds less water than its cooked sibling. That is
    false, and CIQUAL says so plainly: roasting drives water off (turkey 75.4
    raw, 66.7 roasted) but steaming puts it back (trout 73.9 raw, 75.0
    steamed). Eighty-six families "failed" a check that was simply wrong about
    cooking.

    Water discriminates in exactly one place, and it happens to be the place
    this feature is about: **dry goods**. Nothing that is stored dry — rice,
    pasta, polenta, pulses, flour — can be above about 20 g/100 g of water, and
    nothing boiled in water can be below about 40. So the check is narrowed to
    that, in both directions:

      * a row called raw whose water is at or above 40 while a sibling called
        prepared is at or below 20 is an inversion no cooking method produces,
        and is a bug in the name rule;
      * a family where the raw row is under 20 and the prepared row over 40 is
        a family the rule got right, and those are counted so the coverage of
        the confirmation is visible rather than assumed.

    Outside dry goods there is nothing in CIQUAL to check the names against.
    That is stated rather than papered over: the preparation state of a piece
    of meat is known here only because the name says so."""
    DRY = 20.0
    WET = 40.0

    families = {}
    for food in foods:
        head = fold(food["name"]).split(",")[0]
        families.setdefault(head, []).append(food)

    inversions = 0
    confirmed = 0
    for head, members in sorted(families.items()):
        raws = [f for f in members if f["state"] == 1 and f["water"] is not None]
        cooked = [f for f in members if f["state"] == 2 and f["water"] is not None]
        if not raws or not cooked:
            continue
        if any(r["water"] >= WET for r in raws) and any(c["water"] <= DRY for c in cooked):
            inversions += 1
            print("inversion: %s" % head)
            for f in raws + cooked:
                print("   %-9s %5d %-58s water %s"
                      % ("raw" if f["state"] == 1 else "prepared", f["code"], f["name"][:58], f["water"]))
        elif all(r["water"] <= DRY for r in raws) and all(c["water"] >= WET for c in cooked):
            confirmed += 1

    print("dry-goods check: %d families confirmed, %d inversions" % (confirmed, inversions))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    build(sys.argv[1], sys.argv[2])
