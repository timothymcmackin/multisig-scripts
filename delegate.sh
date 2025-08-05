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

# Get account info
output=$(octez-client show address multisig_staker --show-secret)

# Parse the output
address=$(echo "$output" | grep '^Hash:' | awk '{print $2}')
public_key=$(echo "$output" | grep '^Public Key:' | awk '{print $3}')
secret_key=$(echo "$output" | grep '^Secret Key:' | awk '{print $3}' | sed -n 's/^unencrypted://p')

echo "Address: $address"
# echo "Public Key: $public_key"
# echo "Secret Key: $secret_key"

json=$(octez-client share bls secret key "$secret_key" between 3 shares with threshold 2)

# Extract and print values using jq
proof=$(echo "$json" | jq -r '.proof')
secret1=$(echo "$json" | jq -r '.secret_shares[0].secret_key')
secret2=$(echo "$json" | jq -r '.secret_shares[1].secret_key')
secret3=$(echo "$json" | jq -r '.secret_shares[2].secret_key')

# echo "Proof: $proof"
echo "Secret Key 1: $secret1"
echo "Secret Key 2: $secret2"
echo "Secret Key 3: $secret3"

octez-client import secret key alice_multi unencrypted:"$secret1" -f
octez-client import secret key bob_multi unencrypted:"$secret2" -f
octez-client import secret key charlie_multi unencrypted:"$secret3" -f

counter_result=$(octez-client rpc get chains/main/blocks/head/context/contracts/"$address"/counter)
counter_string=$(echo "$counter_result" | tr -d '"')

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

counter=$(convert_int $counter_string)

counter1=$((counter + 1))
counter2=$((counter + 2))

# echo $counter $counter1 $counter2 $counter3

branch=$(octez-client rpc get chains/main/blocks/head~2/hash)

operation_json="{ \"branch\":
  $branch,
      \"contents\":
        [ { \"kind\": \"reveal\",
            \"source\": \"$address\", \"fee\": \"735\",
            \"counter\": \"$counter1\", \"gas_limit\": \"3251\", \"storage_limit\": \"0\",
            \"public_key\":
              \"$public_key\",
            \"proof\":
              \"$proof\" },
          { \"kind\": \"delegation\",
            \"source\": \"$address\", \"fee\": \"448\",
            \"counter\": \"$counter2\", \"gas_limit\": \"1673\", \"storage_limit\": \"0\",
            \"delegate\": \"$baker\" } ] }"

quoted_operation="${operation_json}"
# echo $quoted_operation
operation_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/operations with '$quoted_operation'"
echo $operation_cmd
operation_bytes=$(eval "$operation_cmd" | tr -d '"')
# echo $operation_bytes
operation_bytes_03="03$operation_bytes"
operation_bytes_0x03="0x03$operation_bytes"

alice_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for alice_multi)
# echo $alice_sig_full
alice_sig=$(echo "$alice_sig_full" | grep '^Signature:' | awk '{print $2}')
echo $alice_sig

bob_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for bob_multi)
# echo $bob_sig_full
bob_sig=$(echo "$bob_sig_full" | grep '^Signature:' | awk '{print $2}')
echo $bob_sig


threshold_json="{
\"public_key\": \"$public_key\",
\"message\": \"$operation_bytes_03\",
\"signature_shares\": [{ \"id\": 1, \"signature\": \"$alice_sig\" },
{ \"id\": 2, \"signature\": \"$bob_sig\" } ]}"

quoted_threshold="${threshold_json}"
echo $quoted_threshold
threshold_cmd="octez-client threshold bls signatures '$quoted_threshold'"
threshold_sig=$(eval "$threshold_cmd")
echo $threshold_sig

signed_operations_json="{ \"branch\":
  $branch,
      \"contents\":
        [ { \"kind\": \"reveal\",
            \"source\": \"$address\", \"fee\": \"735\",
            \"counter\": \"$counter1\", \"gas_limit\": \"3251\", \"storage_limit\": \"0\",
            \"public_key\":
              \"$public_key\",
            \"proof\":
              \"$proof\" },
          { \"kind\": \"delegation\",
            \"source\": \"$address\", \"fee\": \"448\",
            \"counter\": \"$counter2\", \"gas_limit\": \"1673\", \"storage_limit\": \"0\",
            \"delegate\": \"$baker\" } ],
 \"signature\" : \"$threshold_sig\"}"

echo $signed_operations_json
signed_operations_quoted="${signed_operations_json}"
signed_operations_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/signed_operations with '$signed_operations_quoted'"
echo $signed_operations_cmd
fully_signed_operation=$(eval "$signed_operations_cmd")

post_operation_quoted="${fully_signed_operation}"
post_operation_cmd="octez-client rpc post /injection/operation with '$post_operation_quoted'"
echo $post_operation_cmd
operation_hash=$(eval "$post_operation_cmd" | tr -d '"')
echo $operation_hash
sleep 10s
receipt_cmd="octez-client get receipt for $operation_hash"
echo $receipt_cmd
eval $receipt_cmd


