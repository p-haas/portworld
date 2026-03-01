# Port:🌍

Open-source framework to plug your AI expertise into the real world through smart glasses.

## Executive Summary

`Port:🌍` lets teams bring existing AI solutions to field operations with native vision + voice pipelines:

- Voice in: Voxtral (customizable)
- Vision in: image/video context (base64 + query bundles), Nemotron 12B and other vision models (customizable)
- Agent orchestration: Strands-compatible routing with optional Weave tracing
- Voice out: ElevenLabs streaming

Core idea: you own the domain expertise and agent logic, Port brings the real-world glasses runtime and transport layer.
Think of it as an open-source "openclaw" for smart-glasses applications.

## What Port Solves

- Removes hardcoded/legacy setup patterns and versioned branding
- Provides lean runtime personalization instead of massive `.env` churn
- Makes agent behavior explicit and pluggable
- Keeps iOS + backend contracts stable for contributors

## Typical Use Cases

- Guided tours and real-time cultural assistance
- Accessibility support in mobility or vision-constrained contexts
- Field operations: plumbing, maintenance, inspection, commercial assistance

## Architecture

1. Glasses + iOS capture audio/video/photo context.
2. Backend pipeline resolves runtime profile, selected agent, and model/tool routing.
3. Strands-compatible driver path can orchestrate the agent/tool chain.
4. Weave/console tracing can observe runs.
5. TTS streaming returns audio to the client (including live LLM-token relay path).

## Repository Layout

- `framework/` - Port:🌍 backend framework (FastAPI, runtime config, pipeline, agents, providers)
- `IOS/` - Port:🌍 iOS client (`PortWorld`) for Meta Wearables DAT integration

## Quick Start

### Backend

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r framework/requirements.txt
cp framework/.env.example .env
python framework/app.py
```

### iOS

```bash
open IOS/PortWorld.xcodeproj
```

Set minimal iOS runtime config in `IOS/Info.plist`:

- `SON_BACKEND_BASE_URL`
- `SON_WS_PATH`
- `SON_VISION_PATH`
- `SON_QUERY_PATH`
- optional: `SON_API_KEY`, `SON_BEARER_TOKEN`

## API Surface (Backend)

- `GET /healthz`
- `GET /v1/agents`
- `GET /v1/config/quickstart-template`
- `POST /v1/pipeline`
- `POST /v1/pipeline/tts-stream`
- `POST /v1/elevenlabs/stream`

## Open Source Personalization Model

Lean by default:

- Keep stable defaults in code/templates
- Override at runtime only what is needed (`runtime_config`)
- Add custom agents/tools without editing core pipeline

This keeps onboarding short for teams integrating their own AI solution.

## License

Recommended for public release: Apache-2.0 (or MIT).
