class AuthService:
    
    def register(self):
        pass
    
    def login(self, request):
        return {
            "message": f"Bienvenido {request.email}"
        }
    
    def logout(self):
        pass