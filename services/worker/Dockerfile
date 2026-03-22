FROM python:3.12-slim

RUN groupadd --gid 1000 app \
    && useradd --uid 1000 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY app.py /app/app.py

RUN chown -R app:app /app

USER 1000

ENV QUEUE_DIR=/queue
ENV SERVICE_NAME=worker
ENV APP_ENV=unknown
ENV WORKER_MODE=consume

CMD ["python", "/app/app.py"]

