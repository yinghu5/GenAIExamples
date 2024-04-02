#!/bin/bash

# eval dataset
FILEDIR=/mnt/disk3/minminhou/datasets/patronus_enterprise_pii/ #/media/SSD8T/minminho/datasets/patronus_enterprise_pii/
FILENAME=patronus_enterprise_pii_v2.csv #annotation_mixtral_instruct_v2_prompt_wrong_predictions.csv #
OUTPUT=test_prefilter_two_prompts_v2_preprocess

#model
MODEL=mistralai/Mixtral-8x7B-Instruct-v0.1
TOKENIZER=mistralai/Mixtral-8x7B-Instruct-v0.1
MAXNEWTOKEN=256
MODELDIR=/mnt/disk3/minminhou/huggingface/transformers/ #/media/SSD8T/minminho/vllm_models/

BATCHSIZE=2
TP=4

python annotate_data_with_llm.py \
--filedir $FILEDIR \
--filename $FILENAME \
--output $OUTPUT \
--model $MODEL \
--tokenizer $TOKENIZER \
--max_new_tokens $MAXNEWTOKEN \
--batch_size $BATCHSIZE \
--tp_size $TP \
--run_prefilters \
--vllm_offline \
--rerun_failed \
--run_eval


