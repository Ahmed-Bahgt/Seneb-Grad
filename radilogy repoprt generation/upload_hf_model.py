from huggingface_hub import HfApi

# ==============================================================================
# يرجى تعديل البيانات التالية قبل التشغيل:
# ==============================================================================

# 1. اسم الـ Space أو الـ Repo بتاعك على Hugging Face
# مثال: "Ahmed-Bahgt/radilogy-api" أو "Ahmed-Bahgt/rehab-system"
REPO_ID = "AhmedBahgt/tamren-tech-backend" 

# 2. نوع الـ Repo 
# إذا كنت رفعته كـ Space خليها "space"، وإذا كـ Model خليها "model"
REPO_TYPE = "space" 

# 3. التوكن الخاص بك (يجب أن يكون Write Token من إعدادات حسابك)
# للحصول عليه: https://huggingface.co/settings/tokens
TOKEN = "YOUR_HUGGING_FACE_TOKEN_HERE" 

# ==============================================================================

def main():
    print("🚀 بدء رفع ملف الموديل...")
    api = HfApi()
    
    try:
        api.upload_file(
            path_or_fileobj="../custom_backend/main.py",
            path_in_repo="custom_backend/main.py",  



            repo_id=REPO_ID,
            repo_type=REPO_TYPE,
            token=TOKEN,
        )
        print("✅ تم رفع requirements.txt بنجاح إلى Hugging Face!")
        print("💡 الآن يمكنك إعادة تشغيل الـ Space أو سيقوم هو بإعادة التشغيل تلقائياً، وسيعمل الـ Grad-CAM والـ Classification بشكل صحيح.")
    except Exception as e:
        print(f"❌ حدث خطأ أثناء الرفع:\n{e}")
        print("\nتأكد من:")
        print("1. صحة الـ REPO_ID (اسم المستخدم/اسم المشروع)")
        print("2. صحة الـ TOKEN وأن لديه صلاحيات Write")

if __name__ == "__main__":
    main()
