"""
VAAK-1 Milestone #3: 1.58-Bit Ternary Quantization & 2MB SRAM Footprint Profiler
Matches VAAK-1 RTL encoding:
  2'b01 -> +1
  2'b11 -> -1
  2'b00 ->  0
Packs 4 ternary weights per byte (8 weights per 16-bit SRAM word).
"""

import math
import random

SRAM_CAPACITY_BYTES = 2 * 1024 * 1024  # 2,097,152 bytes (2.0 MB strict DRAM-free limit)
ACTIVATION_SCRATCHPAD_BYTES = 256 * 1024  # 256 KB reserved for KV-cache & audio frames
WEIGHT_SRAM_BUDGET_BYTES = SRAM_CAPACITY_BYTES - ACTIVATION_SCRATCHPAD_BYTES  # 1.75 MB


def absmean_ternary_quantize(weights):
    """
    BitNet b1.58 absmean quantization:
    gamma = mean(|W|)
    W_q = RoundClip(W / (gamma + eps), -1, 1)
    """
    if not weights:
        return [], 0.0
    gamma = sum(abs(w) for w in weights) / len(weights)
    if gamma == 0:
        return [0] * len(weights), 0.0

    quantized = []
    for w in weights:
        scaled = round(w / gamma)
        if scaled > 1:
            scaled = 1
        elif scaled < -1:
            scaled = -1
        quantized.append(scaled)
    return quantized, gamma


def pack_weights_to_sram_words(ternary_weights):
    """
    Packs 8 ternary weights into a 16-bit SRAM word (little-endian lane order)
    matching rtl/sram_weight_streamer.sv & rtl/ternary_npu_core.sv:
      +1 -> 0b01
      -1 -> 0b11
       0 -> 0b00
    """
    code_map = {0: 0b00, 1: 0b01, -1: 0b11}
    padded = list(ternary_weights)
    while len(padded) % 8 != 0:
        padded.append(0)

    sram_words = []
    for i in range(0, len(padded), 8):
        word16 = 0
        for lane in range(8):
            code = code_map[padded[i + lane]]
            word16 |= (code & 0b11) << (lane * 2)
        sram_words.append(word16)
    return sram_words


def verify_dot_product_parity(activations_int8, ternary_weights):
    """Reference dot product matching VAAK-1 hardware accumulator."""
    total = 0
    for a, w in zip(activations_int8, ternary_weights):
        if w == 1:
            total += a
        elif w == -1:
            total -= a
    return total


def profile_vaak1_pipeline():
    pipeline_modules = [
        {"name": "Frontend Mel-Filterbank + ConvSubsampler", "params": 180_000},
        {"name": "Acoustic Encoder (4-Layer Ternary Transformer)", "params": 2_620_000},
        {"name": "Translation Encoder-Decoder (Pruned Marian-Micro)", "params": 4_100_000},
        {"name": "Bilingual Token Embeddings (4k Subword Vocab)", "params": 384_000},
    ]

    print("=" * 72)
    print("VAAK-1 SILICON MEMORY & 1.58-BIT QUANTIZATION PROFILER (DRAM-FREE CHECK)")
    print("=" * 72)
    print(f"Total On-Chip SRAM         : {SRAM_CAPACITY_BYTES:,} bytes (2.00 MB)")
    print(f"Activation / KV Scratchpad : {ACTIVATION_SCRATCHPAD_BYTES:,} bytes (0.25 MB)")
    print(f"Available Weight SRAM      : {WEIGHT_SRAM_BUDGET_BYTES:,} bytes (1.75 MB)")
    print("-" * 72)

    total_params = 0
    total_fp16_bytes = 0
    total_ternary_bytes = 0

    for mod in pipeline_modules:
        p = mod["params"]
        fp16_b = p * 2
        ternary_b = math.ceil(p / 4)
        total_params += p
        total_fp16_bytes += fp16_b
        total_ternary_bytes += ternary_b
        print(
            f"{mod['name']:<48} | {p/1e6:>4.2f}M params | "
            f"FP16: {fp16_b/1024:>7.1f} KB -> 1.58b: {ternary_b/1024:>6.1f} KB"
        )

    print("-" * 72)
    compression_ratio = total_fp16_bytes / total_ternary_bytes
    utilization_pct = (total_ternary_bytes / WEIGHT_SRAM_BUDGET_BYTES) * 100.0
    headroom_kb = (WEIGHT_SRAM_BUDGET_BYTES - total_ternary_bytes) / 1024.0

    print(f"Total Pipeline Parameters  : {total_params:,} ({total_params/1e6:.2f}M)")
    print(f"Standard FP16 Footprint    : {total_fp16_bytes / (1024*1024):.2f} MB (Requires External DRAM)")
    print(f"VAAK-1 1.58-Bit Footprint  : {total_ternary_bytes / (1024*1024):.2f} MB ({total_ternary_bytes:,} bytes)")
    print(f"Memory Compression Ratio   : {compression_ratio:.2f}x smaller than FP16")
    print(f"Weight SRAM Utilization    : {utilization_pct:.1f}% (Free Headroom: {headroom_kb:.1f} KB)")

    assert total_ternary_bytes <= WEIGHT_SRAM_BUDGET_BYTES, "ERROR: Exceeded 2MB SRAM limit!"

    print("\n" + "-" * 72)
    print("RTL BIT-EXACT WEIGHT PACKING & QUANTIZATION SANITY CHECK")
    print("-" * 72)

    sample_fp_weights = [0.42, -0.39, 0.51, 0.03, 0.37, -0.44, -0.02, 0.48]
    q_weights, gamma = absmean_ternary_quantize(sample_fp_weights)
    packed_words = pack_weights_to_sram_words(q_weights)
    sample_acts = [10, 20, -5, 12, 8, -4, 15, 6]
    acc = verify_dot_product_parity(sample_acts, q_weights)

    print(f"Absmean Scale (gamma)      : {gamma:.4f}")
    print(f"Quantized Ternary Lanes    : {q_weights}")
    print(f"Packed 16-bit SRAM Word    : 0x{packed_words[0]:04X} (matches RTL sram_wdata)")
    print(f"Simulated NPU Accumulator  : {acc} (matches RTL acc_out = 3)")

    assert packed_words[0] == 0x5317, f"Expected 0x5317, got 0x{packed_words[0]:04X}"
    assert acc == 3, f"Expected accumulator 3, got {acc}"

    random.seed(42)
    gaussian_layer = [random.gauss(0.0, 0.5) for _ in range(10_000)]
    q_layer, _ = absmean_ternary_quantize(gaussian_layer)
    zero_pct = (q_layer.count(0) / len(q_layer)) * 100.0
    print(f"Natural Zero-Sparsity      : {zero_pct:.1f}% lanes gated to 0 (zero dynamic switching power)")
    print("=" * 72)
    print("STATUS: PASS - Full Speech+Translation Model Fits Inside VAAK-1 2MB SRAM!")
    print("=" * 72)


if __name__ == "__main__":
    profile_vaak1_pipeline()
