import models, utils
from database import SessionLocal

db = SessionLocal()
admin_email = "admin@tamren.tech"
admin = db.query(models.Admin).filter(models.Admin.email == admin_email).first()
if admin:
    print(f"Current hash: {admin.password_hash}")
    admin.password_hash = utils.hash_password("admin123")
    db.commit()
    print("Admin password forced to hash: admin123")
else:
    print("Admin not found")
db.close()
