#!/bin/bash
set -e

MULTI_NAME="mn_multi"
MN_ONE="mn_one"
MN_TWO="mn_two"
MN_THREE="mn_three"
pop_filename="$MULTI_NAME""_pop"

generate_cmd="octez-client gen keys $MULTI_NAME -s bls -f"
echo "$generate_cmd"
eval $generate_cmd
echo

show_key_cmd="octez-client show address $MULTI_NAME --show-secret"
echo "$show_key_cmd"
show_key_result=$(eval "$show_key_cmd")
echo "$show_key_result"
echo
multi_private_key_full=$(echo "$show_key_result" | grep '^Secret Key:' | awk '{print $3}')
# Trim off the "unencrypted:"
multi_private_key="${multi_private_key_full#unencrypted:}"
multi_pk=$(echo "$show_key_result" | grep '^Public Key:' | awk '{print $3}')
multi_address=$(echo "$show_key_result" | grep '^Hash:' | awk '{print $2}')
echo "Address: $multi_address"
echo "Public key: $multi_pk"
echo "Secret key: $multi_private_key"

echo

share_cmd="octez-client share bls secret key '$multi_private_key' between 3 shares with threshold 2"
echo "$share_cmd"
share_result=$(eval "$share_cmd")
echo "$share_result"

echo

multi_pk=$(echo "$share_result" | jq .public_key | tr -d '"')
echo "Multi pk: $multi_pk"
multi_pop=$(echo "$share_result" | jq .proof | tr -d '"')

rm_cmd="rm $pop_filename || true"
eval $rm_cmd
write_pop_cmd="echo $multi_pop > $pop_filename"
eval $write_pop_cmd

mn_one_secret=$(echo "$share_result" | jq .secret_shares.[0].secret_key | tr -d '"')
mn_two_secret=$(echo "$share_result" | jq .secret_shares.[1].secret_key | tr -d '"')
mn_three_secret=$(echo "$share_result" | jq .secret_shares.[2].secret_key | tr -d '"')

echo

remove_1_cmd="octez-client forget address $MN_ONE -f || true"
remove_2_cmd="octez-client forget address $MN_TWO -f || true"
remove_3_cmd="octez-client forget address $MN_THREE -f || true"
eval $remove_1_cmd
eval $remove_2_cmd
eval $remove_3_cmd

import_1_cmd="octez-client import secret key $MN_ONE unencrypted:$mn_one_secret"
import_2_cmd="octez-client import secret key $MN_TWO unencrypted:$mn_two_secret"
import_3_cmd="octez-client import secret key $MN_THREE unencrypted:$mn_three_secret"
import_1_result=$(eval "$import_1_cmd")
import_2_result=$(eval "$import_2_cmd")
import_3_result=$(eval "$import_3_cmd")
mn_1_addr="${import_1_result#Tezos address added: }"
mn_2_addr="${import_2_result#Tezos address added: }"
mn_3_addr="${import_3_result#Tezos address added: }"
echo "Participant addresses:"
echo "$mn_1_addr"
echo "$mn_2_addr"
echo "$mn_3_addr"

forget_cmd="octez-client forget address $MULTI_NAME -f"
import_cmd="octez-client import public key $MULTI_NAME unencrypted:$multi_pk"
echo "$forget_cmd"
eval $forget_cmd
echo "$import_cmd"
eval $import_cmd