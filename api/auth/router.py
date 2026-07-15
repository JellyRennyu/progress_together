from fastapi import APIRouter
from .schemas import LoginRequest, RegisterRequest
from .service import AuthService

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

service = AuthService()

@router.post("/login")
def login(request: LoginRequest):
    return service.login(request)

@router.post("/register")
def register(request: RegisterRequest):
    return service.register(request)