#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a SystemVerilog FIR coefficient package.")
    parser.add_argument("--coeff-file", required=True, help="Path to integer coefficient text file")
    parser.add_argument("--output", required=True, help="Path to generated SystemVerilog package")
    parser.add_argument("--coeff-width", type=int, required=True, help="Signed coefficient width in bits")
    parser.add_argument("--frac-bits", type=int, required=True, help="Coefficient fractional bit count")
    parser.add_argument("--package-name", default="fir_coeffs_pkg", help="SystemVerilog package name")
    return parser.parse_args()


def read_coeffs(coeff_path: Path) -> list[int]:
    coeffs = []
    for raw_line in coeff_path.read_text().splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        coeffs.append(int(stripped))
    if not coeffs:
        raise ValueError(f"No coefficients found in {coeff_path}")
    return coeffs


def format_coeff(width: int, value: int) -> str:
    sign = "-" if value < 0 else ""
    return f"{sign}{width}'sd{abs(value)}"


def generate_package_text(
    package_name: str,
    coeffs: list[int],
    coeff_width: int,
    frac_bits: int,
    coeff_file: str,
) -> str:
    lines = []
    lines.append(f"package {package_name};")
    lines.append(f"  localparam int FIR_NUM_TAPS = {len(coeffs)};")
    lines.append(f"  localparam int FIR_COEFF_WIDTH = {coeff_width};")
    lines.append(f"  localparam int FIR_COEFF_FRAC_BITS = {frac_bits};")
    lines.append("  typedef logic signed [FIR_COEFF_WIDTH-1:0] fir_coeff_t;")
    lines.append("")
    lines.append(f"  // Generated from {coeff_file}")
    lines.append("  function automatic fir_coeff_t fir_coeff(input int idx);")
    lines.append("    case (idx)")
    for idx, coeff in enumerate(coeffs):
        lines.append(f"      {idx}: fir_coeff = {format_coeff(coeff_width, coeff)};")
    lines.append("      default: fir_coeff = '0;")
    lines.append("    endcase")
    lines.append("  endfunction")
    lines.append("endpackage")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    coeff_path = Path(args.coeff_file).resolve()
    output_path = Path(args.output).resolve()
    display_coeff_file = Path(args.coeff_file).as_posix()

    coeffs = read_coeffs(coeff_path)
    package_text = generate_package_text(
        package_name=args.package_name,
        coeffs=coeffs,
        coeff_width=args.coeff_width,
        frac_bits=args.frac_bits,
        coeff_file=display_coeff_file,
    )

    output_path.write_text(package_text)


if __name__ == "__main__":
    main()
