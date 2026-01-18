FROM python:3.12-slim

WORKDIR /app
COPY benchmarks/servers/fastapi/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY benchmarks/servers/fastapi/app.py ./

ENV PORT=8005
EXPOSE 8005

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8005"]
