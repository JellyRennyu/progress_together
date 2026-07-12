# Llibraries of main.py
from fastapi import FastAPI

#API Services import
from api.auth.router import router as auth_router

#API instance
app = FastAPI()

# Test Get
@app.get("/")
def inicio():
    return {"message": "Hola mundo"}

app.include_router(auth_router)