FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY fantasy_assistant ./fantasy_assistant

ENV DATABASE_URL=sqlite:////data/fantasy_assistant.db

EXPOSE 8000

CMD ["uvicorn", "fantasy_assistant.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
