FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml README.md ./
COPY crlab ./crlab
RUN pip install --no-cache-dir .
ENV PORT=8000
EXPOSE 8000
CMD ["sh", "-c", "uvicorn crlab.api:production_app --factory --host 0.0.0.0 --port ${PORT}"]
