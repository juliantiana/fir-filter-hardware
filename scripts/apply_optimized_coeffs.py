#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    opt_root = Path(__file__).resolve().parents[1]
    coeff_file = opt_root / "results" / "coeffs" / "fir_lowpass_equiripple_taps211_weight160_q1_19_int.txt"
    output_file = opt_root / "rtl" / "include" / "fir_coeffs_pkg.sv"
    generator = opt_root / "scripts" / "generate_sv_coeff_pkg.py"

    if not coeff_file.exists():
        print(f"Optimized coefficient file not found: {coeff_file}", file=sys.stderr)
        print("Run matlab/design_fir_equiripple_optimized.m first.", file=sys.stderr)
        return 1

    output_file.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        sys.executable,
        str(generator),
        "--coeff-file",
        str(coeff_file),
        "--output",
        str(output_file),
        "--coeff-width",
        "20",
        "--frac-bits",
        "19",
    ]

    subprocess.run(cmd, check=True)
    print(f"Wrote optimized coefficient package to {output_file}")
    print("Use FIR_COEFF_PKG to point Quartus at this package without modifying the public repo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
