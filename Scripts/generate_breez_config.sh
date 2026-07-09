#!/bin/bash

OUTPUT_FILE="${1:-"SignalUI/Payments/BreezSdkConfig.swift"}"

if [ -z "$BREEZ_API_KEY" ]; then
    echo "Error: BREEZ_API_KEY environment variable is not set"
    exit 1
fi

cat > "$OUTPUT_FILE" << EOF
//
// BreezSdkConfig.swift
// Auto-generated on $(date +"%Y-%m-%d") — do not edit manually
//

import BreezSdkSpark

let breezSdkConfig: Config = {
    // Start from Breez's defaults, then apply Radar overrides. Everything not set
    // below (sync interval, external input parsers, real-time sync, private-mode
    // default, etc.) intentionally inherits Breez defaults. Using defaultConfig()
    // keeps this file compiling across SDK versions that add/rename Config fields.
    var config = defaultConfig(network: Network.mainnet)
    config.apiKey = "$BREEZ_API_KEY"
    config.lnurlDomain = "radar.cash"
    config.preferSparkOverLightning = true
    config.maxDepositClaimFee = MaxFee.networkRecommended(leewaySatPerVbyte: 5)
    return config
}()
EOF

echo "Generated: $OUTPUT_FILE"
