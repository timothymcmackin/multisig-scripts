#!/bin/bash

amount_to_send_mutez=1000000 # 1 tez
destination=tz1fsVnw7VQD73kUDB8ZWc67GWvCjTEibi9A

# Get account info
output=$(octez-client show address multisig_staker --show-secret)

# Parse the output
address=$(echo "$output" | grep '^Hash:' | awk '{print $2}')
public_key=$(echo "$output" | grep '^Public Key:' | awk '{print $3}')
# secret_key=$(echo "$output" | grep '^Secret Key:' | awk '{print $3}' | sed -n 's/^unencrypted://p')

echo "Address: $address"

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

branch=$(octez-client rpc get chains/main/blocks/head~2/hash)

operation_json="{ \"branch\":
  $branch,
      \"contents\":
        [ { \"kind\": \"transaction\",
            \"source\": \"$address\", \"fee\": \"1000\",
            \"counter\": \"$counter1\", \"gas_limit\": \"3674\", \"storage_limit\": \"0\",
            \"amount\": \"$amount_to_send_mutez\",
            \"destination\": \"$destination\" } ] }"

quoted_operation="${operation_json}"
# echo $quoted_operation
# operation_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/operations with '$quoted_operation'"
operation_cmd="octez-codec encode 023-PtSeouLo.operation.unsigned from '$quoted_operation'"
echo $operation_cmd
operation_bytes=$(eval "$operation_cmd" | tr -d '"')
# echo $operation_bytes
operation_bytes_03="03$operation_bytes"
operation_bytes_0x03="0x03$operation_bytes"

echo "octez-client sign bytes ..."
alice_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for alice_multi)
# echo $alice_sig_full
alice_sig=$(echo "$alice_sig_full" | grep '^Signature:' | awk '{print $2}')
# echo $alice_sig

bob_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for bob_multi)
# echo $bob_sig_full
bob_sig=$(echo "$bob_sig_full" | grep '^Signature:' | awk '{print $2}')
# echo $bob_sig


threshold_json="{
\"public_key\": \"$public_key\",
\"message\": \"$operation_bytes_03\",
\"signature_shares\": [{ \"id\": 1, \"signature\": \"$alice_sig\" },
{ \"id\": 2, \"signature\": \"$bob_sig\" } ]}"

quoted_threshold="${threshold_json}"
# echo $quoted_threshold
threshold_cmd="octez-client threshold bls signatures '$quoted_threshold'"
echo "octez-client threshold bls signatures ..."
threshold_sig=$(eval "$threshold_cmd")
# echo $threshold_sig

signed_operations_json="{ \"branch\":
  $branch,
      \"contents\":
        [ { \"kind\": \"transaction\",
            \"source\": \"$address\", \"fee\": \"1000\",
            \"counter\": \"$counter1\", \"gas_limit\": \"3674\", \"storage_limit\": \"0\",
            \"amount\": \"$amount_to_send_mutez\",
            \"destination\": \"$destination\" } ],
 \"signature\" : \"$threshold_sig\"}"

# echo $signed_operations_json
signed_operations_quoted="${signed_operations_json}"
# signed_operations_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/signed_operations with '$signed_operations_quoted'"
signed_operations_cmd="octez-codec encode 023-PtSeouLo.operation from '$signed_operations_quoted'"

echo $signed_operations_cmd
# echo "octez-client rpc post"
fully_signed_operation=$(eval "$signed_operations_cmd")
echo $fully_signed_operation

post_operation_quoted="${fully_signed_operation}"
post_operation_cmd="octez-client rpc post /injection/operation with '\"$post_operation_quoted\"'"
echo $post_operation_cmd
operation_hash=$(eval "$post_operation_cmd" | tr -d '"')
echo "operation hash: $operation_hash"
sleep 10s
receipt_cmd="octez-client get receipt for $operation_hash"
echo $receipt_cmd
eval $receipt_cmd


