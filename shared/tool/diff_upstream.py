import os

UP = "LearningObjects/DITING-1.4.3/lib/ui"
MINE = "shared/lib/ui"
LETTERS = set(chr(c) for c in range(97, 123))


def dart_names(path):
    if not os.path.isdir(path):
        return []
    return sorted(f for f in os.listdir(path) if f.endswith(".dart"))


def lines(path):
    return sum(1 for _ in open(path, encoding="utf-8"))


def is_part_of(name, roots):
    stem = name[:-5]
    if stem in roots:
        return False
    head, _, _ = stem.rpartition("_")
    return head in roots


def main():
    up = dart_names(UP)
    mine = dart_names(MINE)
    up_roots = [f[:-5] for f in up]
    mine_roots = [f[:-5] for f in mine if not is_part_of(f, set(f2[:-5] for f2 in mine))]

    print("UP files", len(up), "lines", sum(lines(os.path.join(UP, f)) for f in up))
    print("MINE files", len(mine), "lines", sum(lines(os.path.join(MINE, f)) for f in mine))
    print("src included by upstream lib/ui itself:")
    print("  UP-ONLY (dropped):")
    for name in up:
        if name[:-5] not in mine_roots:
            print("   ", name, lines(os.path.join(UP, name)))
    print("  MINE-ONLY (added or split):")
    for name in mine:
        if name[:-5] not in up_roots:
            print("   ", name, lines(os.path.join(MINE, name)))
    print("icons:", sorted(set(dart_names(os.path.join(UP, "icons"))) - set(dart_names(os.path.join(MINE, "icons")))))


main()
