#!/usr/bin/env python3
"""Lint check: every Deployment / StatefulSet / DaemonSet in this chart must
expose both `affinity` and `tolerations` so operators can pin or repel pods.

Scans the first-party templates under composio/templates/ (subcharts under
composio/charts/ are vendored and excluded). For each pod-bearing kind the
template must contain a Helm-guarded block of the form:

    {{- with .Values.<path>.affinity }}
    affinity:
      {{- toYaml . | nindent 8 }}
    {{- end }}

and the equivalent `tolerations:` block. The check is intentionally textual
(rather than rendering with `helm template`) because the `with` guards omit
the field entirely when the value is empty -- which is the default -- so a
rendered-output check would silently pass for templates that lack the block.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

POD_KIND_RE = re.compile(r"^kind:\s+(Deployment|StatefulSet|DaemonSet)\s*$", re.MULTILINE)
AFFINITY_RE = re.compile(r"^\s*affinity:\s*$", re.MULTILINE)
TOLERATIONS_RE = re.compile(r"^\s*tolerations:\s*$", re.MULTILINE)


def find_chart_root() -> Path:
    here = Path(__file__).resolve()
    for parent in [here.parent, *here.parents]:
        if (parent / "Chart.yaml").exists():
            return parent
    raise SystemExit("could not locate chart root (Chart.yaml) above this script")


def template_files(chart_root: Path) -> list[Path]:
    return sorted(p for p in (chart_root / "templates").rglob("*.yaml") if p.is_file())


def check_template(path: Path) -> list[str]:
    text = path.read_text()
    if not POD_KIND_RE.search(text):
        return []
    failures: list[str] = []
    if not AFFINITY_RE.search(text):
        failures.append("missing pod-spec `affinity:` block")
    if not TOLERATIONS_RE.search(text):
        failures.append("missing pod-spec `tolerations:` block")
    return failures


def main() -> int:
    chart_root = find_chart_root()
    failures: dict[Path, list[str]] = {}
    checked = 0
    for path in template_files(chart_root):
        problems = check_template(path)
        if problems is None:
            continue
        if POD_KIND_RE.search(path.read_text()):
            checked += 1
            if problems:
                failures[path] = problems

    if failures:
        print("Pod scheduling lint FAILED:")
        for path, problems in failures.items():
            rel = path.relative_to(chart_root.parent)
            for problem in problems:
                print(f"  {rel}: {problem}")
        print(
            "\nEvery Deployment/StatefulSet/DaemonSet must expose both `affinity` and "
            "`tolerations` via a `{{- with .Values.<path>.affinity }}` / `tolerations` "
            "block so operators can pin or repel pods."
        )
        return 1

    print(f"Pod scheduling lint OK ({checked} workload templates checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
