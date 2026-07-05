import Foundation

/// Per-million-token USD pricing for Claude model tiers, used to estimate the
/// cost of usage tokens recorded in a transcript.
public enum ModelPricing {
    public static func costUSD(
        model: String?,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreateTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let lowered = model?.lowercased() ?? ""
        let (inputRate, outputRate): (Double, Double)
        if lowered.contains("haiku") {
            (inputRate, outputRate) = (1.00, 5.00)
        } else if lowered.contains("opus") {
            (inputRate, outputRate) = (15.00, 75.00)
        } else {
            (inputRate, outputRate) = (3.00, 15.00)
        }

        return (Double(inputTokens) * inputRate
            + Double(outputTokens) * outputRate
            + Double(cacheCreateTokens) * inputRate * 1.25
            + Double(cacheReadTokens) * inputRate * 0.1) / 1_000_000
    }
}
