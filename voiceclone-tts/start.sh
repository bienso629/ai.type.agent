#!/bin/bash
export PYTHONIOENCODING=utf-8

if [ -d "$HOME/miniconda/envs/omni_env" ]; then
    eval "$($HOME/miniconda/bin/conda shell.bash hook)"
    conda activate omni_env
    python -m uvicorn api:app --host 0.0.0.0 --port 8981
elif [ -f "./.venv/bin/python" ]; then
    ./.venv/bin/python -m uvicorn api:app --host 0.0.0.0 --port 8981
else
    python3 -m uvicorn api:app --host 0.0.0.0 --port 8981
fi