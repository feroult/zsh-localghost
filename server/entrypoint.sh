#!/bin/bash
# Starts both servers; the container exits as soon as either one dies (the restart policy brings it back).
T="${ZLG_THREADS:-4}"
ARGS=(--host 0.0.0.0 -ngl 0 -t "$T" -c 8192 --no-webui)
/app/llama-server -hf ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF --port 8080 "${ARGS[@]}" &
P1=$!
/app/llama-server -hf ggml-org/Qwen2.5-Coder-0.5B-Q8_0-GGUF --port 8081 "${ARGS[@]}" &
P2=$!
trap 'kill $P1 $P2 2>/dev/null' TERM INT
wait -n $P1 $P2
kill $P1 $P2 2>/dev/null
exit 1
