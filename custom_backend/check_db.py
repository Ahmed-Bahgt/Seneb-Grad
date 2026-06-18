import psycopg2
import os
from dotenv import load_dotenv

load_dotenv()

def check_columns():
    try:
        conn = psycopg2.connect("postgresql://postgres:123456@localhost/tamren_db")
        cur = conn.cursor()
        cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name = 'workout_sessions'")
        columns = [row[0] for row in cur.fetchall()]
        print(f"Columns: {columns}")
        if 'video_url' in columns:
            print("SUCCESS: 'video_url' column exists.")
        else:
            print("MISSING: 'video_url' column not found. Adding it now...")
            cur.execute("ALTER TABLE workout_sessions ADD COLUMN video_url TEXT")
            conn.commit()
            print("SUCCESS: 'video_url' column added.")
        conn.close()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_columns()
