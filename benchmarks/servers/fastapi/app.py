from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def root():
    return "ok"


@app.get("/json")
def json_endpoint():
    return {"ok": True}
