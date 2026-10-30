# Two small llama.cpp servers in one container: the 1.5B model (accurate) on 8080 and the 0.5B (fast) on 8081.
# CPU only on purpose: it must not compete with a GPU that is busy with a bigger model or a game.
# Weights are NOT baked in: they are fetched from Hugging Face on first start into the /models volume
# (keeps the image small and does not redistribute the weights).
FROM ghcr.io/ggml-org/llama.cpp:server
ENV LLAMA_CACHE=/models
VOLUME /models
COPY entrypoint.sh /entrypoint.sh
EXPOSE 8080 8081
HEALTHCHECK --interval=30s --timeout=3s --start-period=120s CMD curl -sf http://localhost:8080/health || exit 1
ENTRYPOINT ["/entrypoint.sh"]
