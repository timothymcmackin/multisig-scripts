#!/bin/bash
set -e

MULTI_NAME="nn_multi"
NN_ONE="nn_one"
NN_TWO="nn_two"
NN_THREE="nn_three"
pop_filename="$MULTI_NAME""_pop"
pk_filename="$MULTI_NAME""_pk"

# generate_1_cmd="octez-client gen keys $NN_ONE -s bls -f"
# generate_2_cmd="octez-client gen keys $NN_TWO -s bls -f"
# generate_3_cmd="octez-client gen keys $NN_THREE -s bls -f"
# eval $generate_1_cmd
# eval $generate_2_cmd
# eval $generate_3_cmd

get_1_cmd="octez-client show address $NN_ONE"
get_1_result=$(eval "$get_1_cmd")
nn_1_pk=$(echo "$get_1_result" | grep '^Public Key:' | awk '{print $3}')
nn_1_address=$(echo "$get_1_result" | grep '^Hash:' | awk '{print $2}')
nn_1_pop=$(eval "octez-client create bls proof for $NN_ONE")

get_2_cmd="octez-client show address $NN_TWO"
get_2_result=$(eval "$get_2_cmd")
nn_2_pk=$(echo "$get_2_result" | grep '^Public Key:' | awk '{print $3}')
nn_2_address=$(echo "$get_2_result" | grep '^Hash:' | awk '{print $2}')
nn_2_pop=$(eval "octez-client create bls proof for $NN_TWO")

get_3_cmd="octez-client show address $NN_THREE"
get_3_result=$(eval "$get_3_cmd")
nn_3_pk=$(echo "$get_3_result" | grep '^Public Key:' | awk '{print $3}')
nn_3_address=$(echo "$get_3_result" | grep '^Hash:' | awk '{print $2}')
nn_3_pop=$(eval "octez-client create bls proof for $NN_THREE")

aggregate_json="[
  {
    \"public_key\": \"$nn_1_pk\",
    \"proof\": \"$nn_1_pop\"
  },
  {
    \"public_key\": \"$nn_2_pk\",
    \"proof\": \"$nn_2_pop\"
  },
  {
    \"public_key\": \"$nn_3_pk\",
    \"proof\": \"$nn_3_pop\"
  }
  ]"
quoted_aggregate="${aggregate_json}"
aggregate_cmd="octez-client aggregate bls public keys '$quoted_aggregate'"
echo "$aggregate_cmd"
account_info_json=$(eval "$aggregate_cmd")
echo "$account_info_json"
MULTISIG_ADDRESS=$(echo "$account_info_json" | jq .public_key_hash)
MULTISIG_PK=$(echo "$account_info_json" | jq .public_key)
echo "multisig PK: $MULTISIG_PK"
echo "multisig address: $MULTISIG_ADDRESS"

import_cmd="octez-client add address $MULTI_NAME $MULTISIG_ADDRESS -f"
eval $import_cmd

echo

NN_1_FRAG_CMD="octez-client create bls proof for $NN_ONE --override-public-key $MULTISIG_PK"
NN_1_FRAG=$(eval "$NN_1_FRAG_CMD")
NN_2_FRAG_CMD="octez-client create bls proof for $NN_TWO --override-public-key $MULTISIG_PK"
NN_2_FRAG=$(eval "$NN_2_FRAG_CMD")
NN_3_FRAG_CMD="octez-client create bls proof for $NN_THREE --override-public-key $MULTISIG_PK"
NN_3_FRAG=$(eval "$NN_3_FRAG_CMD")

aggregate_json="{
  \"public_key\": $MULTISIG_PK,
  \"proofs\": [
    \"$NN_1_FRAG\",
    \"$NN_2_FRAG\",
    \"$NN_3_FRAG\"
  ]
}"
quoted_aggregate_operation="${aggregate_json}"
aggregate_operation_cmd="octez-client aggregate bls proofs '$quoted_aggregate_operation'"
echo $aggregate_operation_cmd
aggregated_proof=$(eval "$aggregate_operation_cmd")

echo

rm_cmd="rm $pop_filename || true"
eval $rm_cmd
write_pop_cmd="echo $aggregated_proof > $pop_filename"
eval $write_pop_cmd

# Is there a way to store the PK with octez-client?
rm_cmd="rm $pk_filename || true"
eval $rm_cmd
write_pop_cmd="echo $MULTISIG_PK > $pk_filename"
eval $write_pop_cmd
