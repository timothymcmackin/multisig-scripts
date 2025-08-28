#!/bin/bash

amount_to_send_mutez=1000000 # 1 tez
destination=tz1QCVQinE8iVj1H2fckqx6oiM85CNJSK9Sx # tim

# Get account info for each account
hilde_output=$(octez-client show address hilde_tz4)
hilde_address=$(echo "$hilde_output" | grep '^Hash:' | awk '{print $2}')
hilde_public_key=$(echo "$hilde_output" | grep '^Public Key:' | awk '{print $3}')

orla_output=$(octez-client show address orla_tz4)
orla_address=$(echo "$orla_output" | grep '^Hash:' | awk '{print $2}')
orla_public_key=$(echo "$orla_output" | grep '^Public Key:' | awk '{print $3}')

pinckney_output=$(octez-client show address pinckney_tz4)
pinckney_address=$(echo "$pinckney_output" | grep '^Hash:' | awk '{print $2}')
pinckney_public_key=$(echo "$pinckney_output" | grep '^Public Key:' | awk '{print $3}')

# Create account

HILDE_PROOF=$(octez-client create bls proof for hilde_tz4)
ORLA_PROOF=$(octez-client create bls proof for orla_tz4)
PINCKNEY_PROOF=$(octez-client create bls proof for pinckney_tz4)

create_account_json="[
{
  \"public_key\": \"$hilde_public_key\",
  \"proof\": \"$HILDE_PROOF\"
},
{
  \"public_key\": \"$orla_public_key\",
  \"proof\": \"$ORLA_PROOF\"
},
{
  \"public_key\": \"$pinckney_public_key\",
  \"proof\": \"$PINCKNEY_PROOF\"
}
]"
quoted_create_account_json="${create_account_json}"
create_account_cmd="octez-client aggregate bls public keys '$quoted_create_account_json'"
account_info_json=$(eval "$create_account_cmd")
MULTISIG_ADDRESS=$(echo "$account_info_json" | jq .public_key_hash)
MULTISIG_PK=$(echo "$account_info_json" | jq .public_key)
echo "multisig address: $MULTISIG_ADDRESS"



HILDE_P_FRAG=$(octez-client create bls proof for hilde_tz4 --override-public-key "$MULTISIG_PK")
ORLA_P_FRAG=$(octez-client create bls proof for orla_tz4 --override-public-key "$MULTISIG_PK")
PINCKNEY_P_FRAG=$(octez-client create bls proof for pinckney_tz4 --override-public-key "$MULTISIG_PK")

aggregate_json="{
  \"public_key\": \"$MULTISIG_PK\",
  \"proofs\": [
    \"$HILDE_P_FRAG\",
    \"$ORLA_P_FRAG\",
    \"$PINCKNEY_P_FRAG\"
  ]
}"

quoted_aggregate_operation="${aggregate_json}"
aggregate_operation_cmd="octez-client aggregate bls proofs '$quoted_aggregate_operation'"
echo $aggregate_operation_cmd
aggregated_proof=$(eval "$aggregate_operation_cmd")

counter_result=$(octez-client rpc get chains/main/blocks/head/context/contracts/"$MULTISIG_ADDRESS"/counter)
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
            \"source\": \"$MULTISIG_ADDRESS\", \"fee\": \"1000\",
            \"counter\": \"$counter1\", \"gas_limit\": \"3674\", \"storage_limit\": \"0\",
            \"amount\": \"$amount_to_send_mutez\",
            \"destination\": \"$destination\" } ] }"

quoted_operation="${operation_json}"
# echo $quoted_operation
operation_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/operations with '$quoted_operation'"
echo "octez-client rpc post ../forge/operations"
# echo $operation_cmd
operation_bytes=$(eval "$operation_cmd" | tr -d '"')
# echo $operation_bytes
operation_bytes_03="03$operation_bytes"
operation_bytes_0x03="0x03$operation_bytes"


hilde_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for hilde_tz4)
hilde_sig=$(echo "$hilde_sig_full" | grep '^Signature:' | awk '{print $2}')
# echo $hilde_sig
echo "octez-client sign bytes (x3)"

orla_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for orla_tz4)
orla_sig=$(echo "$orla_sig_full" | grep '^Signature:' | awk '{print $2}')
# echo $orla_sig

pinckney_sig_full=$(octez-client sign bytes "$operation_bytes_0x03" for pinckney_tz4)
pinckney_sig=$(echo "$pinckney_sig_full" | grep '^Signature:' | awk '{print $2}')
# echo $pinckney_sig

aggregated_json="{
\"public_key\": \"$MULTISIG_PK\",
\"message\": \"$operation_bytes_03\",
\"signature_shares\": [\"$hilde_sig\", \"$orla_sig\", \"$pinckney_sig\"]}"

quoted_aggregate="${aggregated_json}"
# echo $quoted_aggregate
aggregated_cmd="octez-client aggregate bls signatures '$quoted_aggregate'"
echo "octez-client aggregate bls signatures"
aggregated_sig=$(eval "$aggregated_cmd")
# echo $aggregated_sig

signed_operations_json="{ \"branch\":
  $branch,
      \"contents\":
        [ { \"kind\": \"transaction\",
            \"source\": \"$MULTISIG_ADDRESS\", \"fee\": \"1000\",
            \"counter\": \"$counter1\", \"gas_limit\": \"3674\", \"storage_limit\": \"0\",
            \"amount\": \"$amount_to_send_mutez\",
            \"destination\": \"$destination\" } ],
 \"signature\" : \"$aggregated_sig\"}"

# echo $signed_operations_json
signed_operations_quoted="${signed_operations_json}"
signed_operations_cmd="octez-client rpc post /chains/main/blocks/head/helpers/forge/signed_operations with '$signed_operations_quoted'"
# echo $signed_operations_cmd
echo "octez-client rpc post .../forge/signed_operations"
fully_signed_operation=$(eval "$signed_operations_cmd")

post_operation_quoted="${fully_signed_operation}"
post_operation_cmd="octez-client rpc post /injection/operation with '$post_operation_quoted'"
# echo $post_operation_cmd
echo "octez-client rpc post /injection/operation"
operation_hash=$(eval "$post_operation_cmd" | tr -d '"')
echo $operation_hash
sleep 10s
receipt_cmd="octez-client get receipt for $operation_hash"
echo $receipt_cmd
eval $receipt_cmd

