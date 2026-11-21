# VAAK-1 — DRAM-Free 1.58-Bit Ternary Edge AI SoC

**VAAK-1** is an ultra-low-power, external-DRAM-free custom System-on-Chip (SoC) architecture engineered for **offline, phone-free speech transcription and real-time translation** on smart glasses, TWS earbuds, and smartwatches.

## Architecture Charter (v0.1)
* **Host Control Core:** 32-bit RISC-V (`RV32IMC`)
* **AI Compute Engine:** Multiplier-Free 1.58-Bit Ternary NPU (`{-1, 0, +1}` weight routing via parallel adder trees)
* **Memory Hierarchy (Zero External RAM):**
  * `0 MB` External DRAM (eliminates LPDDR power draw & BOM cost)
  * `2 MB` On-Chip SRAM (layer-by-layer streaming activation & KV-cache scratchpad)
  * `16–32 MB` On-Chip eFlash / MRAM (quantized acoustic + translation weights)
* **Target Power Envelope:** `< 20 mW` active inference | `< 0.5 mW` always-on Voice Activity Detection (VAD)

## Repository Layout
* `rtl/` — Synthesizable SystemVerilog hardware blocks (`ternary_npu_core.sv`)
* `tb/` — Cycle-accurate verification testbenches (`tb_ternary_npu.sv`)
* `model_sim/` — Python `< 2 MB` SRAM quantization & latency simulators
* `docs/` — Architecture diagrams, GDSII renders & pitch specs
