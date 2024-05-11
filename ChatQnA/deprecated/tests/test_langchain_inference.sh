#!/bin/bash
# Copyright (c) 2024 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -xe

function test_env_setup() {
    WORKPATH=$(dirname "$PWD")
    LOG_PATH="$WORKPATH/tests"

    REDIS_CONTAINER_NAME="test-redis-vector-db"
    LANGCHAIN_CONTAINER_NAME="test-qna-rag-redis-server"
    CHATQNA_CONTAINER_NAME="test-ChatQnA_server"
    cd $WORKPATH # go to ChatQnA
}

function rename() {
    # Rename the docker container/image names to avoid conflict with local test
    cd ${WORKPATH}
    sed -i "s/container_name: redis-vector-db/container_name: ${REDIS_CONTAINER_NAME}/g" langchain/docker/docker-compose.yml
    sed -i "s/container_name: qna-rag-redis-server/container_name: ${LANGCHAIN_CONTAINER_NAME}/g" langchain/docker/docker-compose.yml
    sed -i "s/image: intel\/gen-ai-examples:qna-rag-redis-server/image: intel\/gen-ai-examples:${LANGCHAIN_CONTAINER_NAME}/g" langchain/docker/docker-compose.yml
    sed -i "s/ChatQnA_server/${CHATQNA_CONTAINER_NAME}/g" serving/tgi_gaudi/launch_tgi_service.sh
}

function launch_tgi_gaudi_service() {
    local card_num=1
    local port=8888
    local model_name="Intel/neural-chat-7b-v3-3"

    cd ${WORKPATH}

    # Reset the tgi port
    sed -i "s/8080/$port/g" langchain/redis/rag_redis/config.py
    sed -i "s/8080/$port/g" langchain/docker/qna-app/app/server.py
    sed -i "s/8080/$port/g" langchain/docker/qna-app/Dockerfile

    docker pull ghcr.io/huggingface/tgi-gaudi:1.2.1
    bash serving/tgi_gaudi/launch_tgi_service.sh $card_num $port $model_name
    sleep 3m # Waits 3 minutes
}

function launch_redis_and_langchain_service() {
    cd $WORKPATH
    export HUGGINGFACEHUB_API_TOKEN=${HUGGINGFACEHUB_API_TOKEN}
    local port=8890
    sed -i "s/port=8000/port=$port/g" langchain/docker/qna-app/app/server.py
    docker compose -f langchain/docker/docker-compose.yml up -d --build

    # Ingest data into redis
    docker exec $LANGCHAIN_CONTAINER_NAME \
        bash -c "cd /ws && python ingest.py > /dev/null"
}

function start_backend_service() {
    cd $WORKPATH
    docker exec $LANGCHAIN_CONTAINER_NAME \
        bash -c "nohup python app/server.py &"
    sleep 1m
}

function run_tests() {
    cd $WORKPATH
    local port=8890
    curl 127.0.0.1:$port/v1/rag/chat \
        -X POST \
        -d "{\"query\":\"What is the total revenue of Nike in 2023?\"}" \
        -H 'Content-Type: application/json' >$LOG_PATH/langchain.log

    curl 127.0.0.1:$port/v1/rag/chat_stream \
        -X POST \
        -d "{\"query\":\"What is the total revenue of Nike in 2023?\"}" \
        -H 'Content-Type: application/json' >$LOG_PATH/langchain_stream.log
}

function check_response() {
    cd $WORKPATH
    echo "Checking response"
    local status=false
    if [[ -f $LOG_PATH/langchain.log ]] && [[ $(grep -c "\$51.2 billion" $LOG_PATH/langchain.log) != 0 ]]; then
        status=truecuda_visible_devicesu
    fi

    if [[ ! -f $LOG_PATH/langchain_stream.log ]] || [[ $(grep -c "billion" $LOG_PATH/langchain_stream.log) == 0 ]]; then
        status=false
    fi

    if [ $status == false ]; then
        echo "Response check failed, please check the logs in artifacts!"
        exit 1
    else
        echo "Response check succeed!"
    fi

}

function run_e2e_tests() {
    cd $WORKPATH/../ui/svelte
    mkdir -p $LOG_PATH/E2E_tests
    conda_env_name="ChatQnA_e2e"

    echo "DOC_BASE_URL = 'http://localhost:8888/v1/rag'" >.env

    export PATH=${HOME}/miniconda3/bin/:$PATH
    conda remove -n ${conda_env_name} --all -y
    conda create -n ${conda_env_name} python=3.12 -y
    source activate ${conda_env_name}

    conda install -c conda-forge nodejs -y && npm install && npm ci && npx playwright install --with-deps
    sudo nohup npm run dev &
    pid=$!
    sleep 20s

    node -v && npm -v && pip list

    echo "[TEST INFO]: ---------E2E test start---------"
    exit_status=0
    npx playwright test || exit_status=$?

    if [ $exit_status -ne 0 ]; then
        echo "[TEST INFO]: ---------E2E test failed---------"
    else
        echo "[TEST INFO]: ---------E2E test passed---------"
    fi

    echo "[TEST INFO]: ---------E2E test finished---------"
    sudo kill -s 9 $pid || true
}

function docker_stop() {
    local container_name=$1
    cid=$(docker ps -aq --filter "name=$container_name")
    if [[ ! -z "$cid" ]]; then docker stop $cid && docker rm $cid; fi
}

function main() {
    test_env_setup
    rename
    docker_stop $CHATQNA_CONTAINER_NAME && docker_stop $LANGCHAIN_CONTAINER_NAME && docker_stop $REDIS_CONTAINER_NAME && sleep 5s

    launch_tgi_gaudi_service
    launch_redis_and_langchain_service
    start_backend_service

    run_tests
    check_response

    if [ $TEST_FRONTEND=="true" ]; then run_e2e_tests; fi

    docker_stop $CHATQNA_CONTAINER_NAME && docker_stop $LANGCHAIN_CONTAINER_NAME && docker_stop $REDIS_CONTAINER_NAME && sleep 5s
    echo y | docker system prune

    exit $exit_status
}

main