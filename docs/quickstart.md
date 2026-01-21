# Quickstart

1. Copy example configs:

   - `configs/providers.yaml.example` -> `configs/providers.yaml`
   - `configs/models.yaml.example` -> `configs/models.yaml`

2. Set provider keys as environment variables.

3. Start the gateway:

   ```sh
   docker compose up -d --build
   ```

4. Send a request:

   ```sh
   curl http://localhost:8080/v1/chat/completions \
     -H 'Content-Type: application/json' \
     -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"hello"}]}'
   ```
