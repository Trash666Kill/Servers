#!/bin/bash

# Close on any error (Optional)
#set -e

NIC0=br_vlan710

ct160716() {
    445() {
        #SMB - CIFS
        # DNAT Rules
        nft add rule inet firelux prerouting iifname "$NIC0" ip protocol tcp tcp dport 445 dnat to 10.0.10.51:445

        # Forward Rules
        nft add rule inet firelux forward ip protocol tcp tcp dport 445 accept
    }

    # Call
    445
}

ct615237() {
    6600() {
        #Music Streaming - MPD Server with USB DAC passthrough
        # DNAT Rules
        nft add rule inet firelux prerouting iifname "$NIC0" ip protocol tcp tcp dport 6600 dnat to 10.0.10.52:6600

        # Forward Rules
        nft add rule inet firelux forward ip protocol tcp tcp dport 6600 accept
    }

    5644() {
        #Music Streaming - MyMPD Web Client
        # DNAT Rules
        nft add rule inet firelux prerouting iifname "$NIC0" ip protocol tcp tcp dport 5644 dnat to 10.0.10.52:5644

        # Forward Rules
        nft add rule inet firelux forward ip protocol tcp tcp dport 5644 accept
    }

    # Call
    6600
    5644
}

ct485153() {
    4553() {
        #Music Streaming - Navidrome
        # DNAT Rules
        nft add rule inet firelux prerouting iifname "$NIC0" ip protocol tcp tcp dport 4533 dnat to 10.0.10.53:4533

        # Forward Rules
        nft add rule inet firelux forward ip protocol tcp tcp dport 4533 accept
    }

    # Call
    4553
}

# Main function to orchestrate the setup
main() {
    RULES="
    ct160716
    ct615237
    ct485153
    "

    for RULE in $RULES
    do
        $RULE
        sleep 4
    done
}

# Execute main function
main