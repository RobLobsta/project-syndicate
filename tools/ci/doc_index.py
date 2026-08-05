#!/usr/bin/env python3
"""Regenerates the section index at the top of each of the thirteen documents.

A document here runs to two thousand lines and a hundred headings, and the only
way to find §7.7 in it was to search for the string. That is fine for a machine
and useless for deciding *whether* a document has anything to say about a topic
before opening it — which is the question a session actually asks.

So each document carries a short index of its own top-level sections, between two
markers, immediately after its title. Top-level sections are the architecture's
chapters: they are numbered, they are stable, and they change roughly never, so
the index is cheap to keep true and does not churn on ordinary edits.

**It is generated rather than written, and checked rather than trusted.**
`LEARNED_FACTS.md` fact 64: a list that must be maintained by hand to stay honest
does not stay honest, and it rots in the direction of looking complete.
`tests/arch/test_doc_indexes.gd` fails the build when a document's index no longer
matches its headings, and this script is how you fix that:

    python3 tools/ci/doc_index.py            # rewrite every index
    python3 tools/ci/doc_index.py --check    # exit 1 if any is stale
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs")

BEGIN = "<!-- SECTION INDEX -->"
END = "<!-- END SECTION INDEX -->"

# Implementation status, declared here and rendered into every document's header.
#
# **A document is normative whether or not anything implements it, and a reader
# cannot tell the two apart from the prose.** Four of the thirteen describe
# software that does not exist: `src/net/` holds one file against doc 12's whole
# authority matrix, and `src/vfx/fusion/`, `src/world/volumes/` and
# `src/assembly/autobuild/` are empty against docs 03, 10 and 06. Somebody
# reading doc 10 has no way to know it is a page of intent where doc 09, which
# reads identically, is fully built and heavily used.
#
# The witness is a source path the claim is checked against, so the banner cannot
# drift: BUILT demands the file exists, PLANNED demands it does not, and PARTIAL
# demands it exists while the document says what is missing.
BUILT = "BUILT"
PARTIAL = "PARTIAL"
PLANNED = "PLANNED"

STATUS = {
    "PART_DATA_SCHEMA.md": (BUILT, "src/autoload/part_registry.gd", ""),
    "GRID_SNAPPING_LOGIC.md": (BUILT, "src/assembly/lattice/placement_validator.gd", ""),
    "PART_FUSION_SHADER.md": (
        PLANNED, "src/vfx/fusion/occupancy_sdf_baker.gd",
        "nothing in `src/vfx/fusion/` exists; parts render as greybox primitives",
    ),
    "DEPENDENCY_TREE_GRAPH.md": (BUILT, "src/assembly/graph/chassis_graph.gd", ""),
    "DYNAMIC_MASS_PHYSICS.md": (
        PARTIAL, "src/motion/motive_system.gd",
        "§8's aerodynamics has no consumer and §7.5's power band is unread",
    ),
    "AUTO_ASSEMBLE_ALGORITHM.md": (
        PLANNED, "src/assembly/autobuild/auto_assembler.gd",
        "`src/assembly/autobuild/` is empty and `tests/generation/` runs nothing",
    ),
    "WEAPON_TARGETING_LOGIC.md": (
        PARTIAL, "src/combat/effectors/effector_system.gd",
        "direct fire and melee only — §5.3's arc, §5.4's guidance and §11's "
        "prediction are unwritten",
    ),
    "COMPONENT_HEALTH_DAMAGE.md": (
        PARTIAL, "src/combat/damage/damage_resolver.gd",
        "§7.3's `DotScheduler`, §9's `VisualDamageController` and §10's repair "
        "path are unwritten",
    ),
    "TERRAIN_CRATER_DEFORMER.md": (BUILT, "src/world/ground/ground_deform_system.gd", ""),
    "PROCEDURAL_STRUCTURE_SLICING.md": (
        PLANNED, "src/world/volumes/convex_slicer.gd",
        "`src/world/volumes/` is empty; only `ManifoldChecker` exists, in "
        "`src/core/util/`",
    ),
    "RESPONSIVE_GARAGE_UI.md": (
        PARTIAL, "src/ui/garage/garage_screen.gd",
        "no touch model, no compact-tier bottom sheet, and §5.3's four helper "
        "classes do not exist",
    ),
    "HEADLESS_NETWORK_SYNC.md": (
        PLANNED, "src/net/net_server.gd",
        "`src/net/` holds one file; there is no server, no snapshot codec and no "
        "prediction",
    ),
    "EXTENSION_PIPELINE.md": (
        PARTIAL, "src/core/util/proxy_mesh_builder.gd",
        "greybox and proxy stages only; no DCC assets have been promoted",
    ),
}

BANNERS = {
    BUILT: "**Status: BUILT.** The subsystem this document specifies exists in "
           "`src/` and is exercised by the suite.",
    PARTIAL: "**Status: PARTIAL — %s.** Everything else here is built and "
             "exercised by the suite.",
    PLANNED: "**Status: PLANNED — %s.** This document is normative for work that "
             "has not been done. Nothing here has been tested against a running "
             "implementation, so treat its figures as intent rather than as "
             "measurements.",
}


def banner(name):
    status, _witness, note = STATUS[name]
    if status == BUILT:
        return BANNERS[BUILT]
    return BANNERS[status] % note

# A top-level section: `## 7. Traction`. The number is required, which is what
# keeps prose headings and the GDScript `##` doc comments inside fenced code
# blocks out of the index.
HEADING = re.compile(r"^## (\d+)\.\s+(.*?)\s*$")

PREAMBLE = (
    "**Sections.** Generated by `tools/ci/doc_index.py` from the headings below "
    "and checked by `tests/arch/test_doc_indexes.gd`; edit the headings, not this "
    "list."
)


def sections(text):
    """Top-level numbered sections, as (number, title), skipping fenced blocks."""
    out = []
    fenced = False
    for line in text.split("\n"):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = HEADING.match(line)
        if m is not None:
            out.append((m.group(1), m.group(2)))
    return out


def index_block(text, name):
    found = sections(text)
    if not found:
        return None
    rows = " · ".join("**%s.** %s" % (n, t) for n, t in found)
    return "%s\n\n%s\n\n%s\n\n%s\n%s" % (BEGIN, banner(name), PREAMBLE, rows, END)


def rewrite(text, name):
    """The document with its index replaced, or inserted after the title."""
    block = index_block(text, name)
    if block is None:
        return text
    if BEGIN in text and END in text:
        head = text[: text.index(BEGIN)]
        tail = text[text.index(END) + len(END) :]
        return head + block + tail
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("# "):
            return "\n".join(lines[: i + 1]) + "\n\n" + block + "\n" + "\n".join(lines[i + 1 :])
    return block + "\n\n" + text


def main(argv):
    check = "--check" in argv
    stale = []
    for name in sorted(os.listdir(DOCS)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(DOCS, name)
        text = open(path).read()
        updated = rewrite(text, name)
        if updated == text:
            continue
        if check:
            stale.append(name)
        else:
            open(path, "w").write(updated)
            print("indexed %s" % name)
    if check and stale:
        print("stale section index in: %s" % ", ".join(stale), file=sys.stderr)
        print("run: python3 tools/ci/doc_index.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
