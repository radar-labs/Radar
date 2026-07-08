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

let breezSdkConfig = Config(
    apiKey: "$BREEZ_API_KEY",
    network: Network.mainnet,
    syncIntervalSecs: 10,
    maxDepositClaimFee: nil,
    lnurlDomain: "radar.cash",
    preferSparkOverLightning: true,
    externalInputParsers: nil,
    useDefaultExternalInputParsers: false,
    realTimeSyncServerUrl: nil,
    privateEnabledDefault: false,
    leafOptimizationConfig: LeafOptimizationConfig(autoEnabled: true, multiplicity: 1),
    tokenOptimizationConfig: TokenOptimizationConfig(autoEnabled: true, targetOutputCount: 5, minOutputsThreshold: 50),
    stableBalanceConfig: nil,
    maxConcurrentClaims: 4,
    sparkConfig: nil,
    backgroundTasksEnabled: true,
    crossChainConfig: nil,
)
EOF

echo "Generated: $OUTPUT_FILE"
