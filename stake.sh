#!/bin/bash

# prerequisites:
# 1. Build v23 RC2 of the Octez client
# 2. octez-client -E https://rpc.seoulnet.teztnets.com config update
# 3. octez-client gen keys multisig_staker -s bls -f
# 4. Get the account some tez from the faucet for tx fees and to stake
# 5. Set the amount to stake below:
amount_to_stake_mutez=10000000 # 10 tez
# 6. Set the address of the account to stake to; make sure they accept stakers; this is zir0h
baker=tz1NNT9EERmcKekRq2vdv6e8TL3WQpY8AXSF
# 7. Run delegate.sh

# Get account info
output=$(octez-client show address multisig_staker --show-secret)

# Parse the output
address=$(echo "$output" | grep '^Hash:' | awk '{print $2}')
public_key=$(echo "$output" | grep '^Public Key:' | awk '{print $3}')
secret_key=$(echo "$output" | grep '^Secret Key:' | awk '{print $3}' | sed -n 's/^unencrypted://p')

echo "Address: $address"
# echo "Public Key: $public_key"
# echo "Secret Key: $secret_key"

# Function to convert a string to a decimal integer
# thanks, chatgpt
convert_int() {
  local input="$1"

  # Check if input is a valid decimal number
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$((10#$input))"
  else
    echo "Error: '$input' is not a valid decimal number" >&2
    return 1
  fi
}

# Stake

counter_result=$(octez-client rpc get chains/main/blocks/head/context/contracts/"$address"/counter)
counter_string=$(echo "$counter_result" | tr -d '"')

counter=$(convert_int $counter_string)
counter3=$((counter + 1))

branch=$(octez-client rpc get chains/main/blocks/head~2/hash)

stake_operation_json="{ \"branch\": $branch,
      \"contents\":
        [ { \"kind\": \"transaction\",
            \"source\": \"$address\", \"fee\": \"808\",
            \"counter\": \"$counter3\", \"gas_limit\": \"5134\", \"storage_limit\": \"0\",
            \"amount\": \"$amount_to_stake_mutez\",
            \"destination\": \"$address\",
            \"parameters\":
              { \"entrypoint\": \"stake\", \"value\": { \"prim\": \"Unit\" } } } ] }"

quoted_stake="${stake_operation_json}"
# echo $quoted_stake
stake_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/operations with '$quoted_stake'"
echo $stake_cmd
stake_sig=$(eval "$stake_cmd" | tr -d '"')
stake_sig_03="03$stake_sig"
stake_sig_0x03="0x03$stake_sig"

alice_stake_sig_full=$(octez-client sign bytes "$stake_sig_0x03" for alice_multi)
alice_stake_sig=$(echo "$alice_stake_sig_full" | grep '^Signature:' | awk '{print $2}')
echo "Alice signature: $alice_stake_sig"

charlie_stake_sig_full=$(octez-client sign bytes "$stake_sig_0x03" for charlie_multi)
charlie_stake_sig=$(echo "$charlie_stake_sig_full" | grep '^Signature:' | awk '{print $2}')
echo "Charlie signature: $charlie_stake_sig"

stake_threshold_json="{
\"public_key\": \"$public_key\",
\"message\": \"$stake_sig_03\",
\"signature_shares\": [{ \"id\": 1, \"signature\": \"$alice_stake_sig\" },
{ \"id\": 3, \"signature\": \"$charlie_stake_sig\" } ]}"
stake_quoted_threshold="${stake_threshold_json}"
stake_threshold_cmd="octez-client threshold bls signatures '$stake_quoted_threshold'"
echo $stake_threshold_cmd
stake_threshold_sig=$(eval "$stake_threshold_cmd")
echo $stake_threshold_sig

stake_operation_signed_json="{ \"branch\": $branch,
      \"contents\":
        [ { \"kind\": \"transaction\",
            \"source\": \"$address\", \"fee\": \"808\",
            \"counter\": \"$counter3\", \"gas_limit\": \"5134\", \"storage_limit\": \"0\",
            \"amount\": \"$amount_to_stake_mutez\",
            \"destination\": \"$address\",
            \"parameters\":
              { \"entrypoint\": \"stake\", \"value\": { \"prim\": \"Unit\" } } } ],
 \"signature\" : \"$stake_threshold_sig\"}"
quoted_stake_signed="${stake_operation_signed_json}"
echo $quoted_stake_signed
stake_stake_signed_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/signed_operations with '$quoted_stake_signed'"
stake_stake_signed_sig=$(eval "$stake_stake_signed_cmd")
echo $stake_stake_signed_sig

stake_operation_quoted="${stake_stake_signed_sig}"
stake_operation_cmd="octez-client rpc post /injection/operation with '$stake_operation_quoted'"
echo $stake_operation_cmd
stake_hash=$(eval "$stake_operation_cmd" | tr -d '"')
echo $stake_hash
sleep 10s
stake_receipt_cmd="octez-client get receipt for $stake_hash"
echo $stake_receipt_cmd
eval $stake_receipt_cmd