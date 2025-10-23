#!/bin/bash
set -e

MULTI_NAME="mn_multi"
MN_ONE="mn_one"
MN_TWO="mn_two"
MN_THREE="mn_three"
pop_filename="$MULTI_NAME""_pop"

amount_to_stake_mutez=10000 # .01 tez

pop=$(cat "$pop_filename")

show_addr_cmd="octez-client show address '$MULTI_NAME'"
echo "$show_addr_cmd"
show_addr_result=$(eval "$show_addr_cmd")
multi_pk=$(echo "$show_addr_result" | grep '^Public Key:' | awk '{print $3}')
multi_address=$(echo "$show_addr_result" | grep '^Hash:' | awk '{print $2}')
echo "Address: $multi_address"
echo "Public key: $multi_pk"

echo

counter_result=$(octez-client rpc get chains/main/blocks/head/context/contracts/"$multi_address"/counter)
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

operation_json="{ \"branch\": $branch,
  \"contents\":
    [ { \"kind\": \"transaction\",
        \"source\": \"$multi_address\", \"fee\": \"808\",
        \"counter\": \"$counter1\", \"gas_limit\": \"5134\", \"storage_limit\": \"0\",
        \"amount\": \"$amount_to_stake_mutez\",
        \"destination\": \"$multi_address\",
        \"parameters\":
          { \"entrypoint\": \"stake\", \"value\": { \"prim\": \"Unit\" } } } ] }"

quoted_operation="${operation_json}"
operation_cmd="octez-codec encode 023-PtSeouLo.operation.unsigned from '$quoted_operation'"
echo $operation_cmd
operation_bytes=$(eval "$operation_cmd" | tr -d '"')
# echo $operation_bytes
operation_bytes_03="03$operation_bytes"
operation_bytes_0x03="0x03$operation_bytes"

echo

one_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for "$MN_ONE")
one_sig=$(echo "$one_sig_full" | grep '^Signature:' | awk '{print $2}')
two_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for "$MN_TWO")
two_sig=$(echo "$two_sig_full" | grep '^Signature:' | awk '{print $2}')
three_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for "$MN_THREE")
three_sig=$(echo "$three_sig_full" | grep '^Signature:' | awk '{print $2}')

aggregated_json="{
\"public_key\": \"$multi_pk\",
\"message\": \"$operation_bytes_03\",
\"signature_shares\": [{ \"id\": 1, \"signature\": \"$one_sig\" },
{ \"id\": 2, \"signature\": \"$two_sig\" } ]}"

quoted_aggregate="${aggregated_json}"
# echo $quoted_aggregate
aggregated_cmd="octez-client threshold bls signatures '$quoted_aggregate'"
echo "$aggregated_cmd"
aggregated_sig=$(eval "$aggregated_cmd")
echo $aggregated_sig

signed_operations_json="{ \"branch\": $branch,
  \"contents\":
    [ { \"kind\": \"transaction\",
        \"source\": \"$multi_address\", \"fee\": \"808\",
        \"counter\": \"$counter1\", \"gas_limit\": \"5134\", \"storage_limit\": \"0\",
        \"amount\": \"$amount_to_stake_mutez\",
        \"destination\": \"$multi_address\",
        \"parameters\":
          { \"entrypoint\": \"stake\", \"value\": { \"prim\": \"Unit\" } } } ],
 \"signature\": \"$aggregated_sig\"}"

echo

echo $signed_operations_json
signed_operations_quoted="${signed_operations_json}"
signed_operations_cmd="octez-codec encode 023-PtSeouLo.operation from '$signed_operations_quoted'"
echo
echo $signed_operations_cmd
fully_signed_operation=$(eval "$signed_operations_cmd")

post_operation_quoted="\"${fully_signed_operation}\""
post_operation_cmd="octez-client rpc post /injection/operation with '$post_operation_quoted'"
echo $post_operation_cmd
operation_hash=$(eval "$post_operation_cmd" | tr -d '"')
echo $operation_hash
sleep 10s
receipt_cmd="octez-client get receipt for $operation_hash"
echo $receipt_cmd
eval $receipt_cmd

