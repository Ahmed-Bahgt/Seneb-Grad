import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2 import sql
import json

LOCAL_DB = "postgresql://postgres:YOUR_LOCAL_PASSWORD@localhost/tamren_db"
NEON_DB = "postgresql://neondb_owner:YOUR_NEON_PASSWORD@ep-quiet-leaf-ah933fzl-pooler.c-3.us-east-1.aws.neon.tech/neondb?sslmode=require"

TABLES = [
    "doctors",
    "patients",
    "radiology_reports"
]

def sync():
    print("🚀 Connecting to local DB...")
    conn_local = psycopg2.connect(LOCAL_DB)
    cur_local = conn_local.cursor(cursor_factory=RealDictCursor)

    print("☁️ Connecting to Neon DB...")
    conn_neon = psycopg2.connect(NEON_DB)
    cur_neon = conn_neon.cursor()

    for table in TABLES:
        print(f"\n📦 Fetching {table} from local...")
        cur_local.execute(f"SELECT * FROM {table}")
        rows = cur_local.fetchall()
        
        if not rows:
            print(f"   Table {table} is empty.")
            continue
            
        print(f"   Found {len(rows)} rows. Pushing to Neon...")
        columns = list(rows[0].keys())
        
        col_names = sql.SQL(', ').join(map(sql.Identifier, columns))
        placeholders = sql.SQL(', ').join(sql.Placeholder() * len(columns))
        
        insert_query = sql.SQL(
            "INSERT INTO {} ({}) VALUES ({}) ON CONFLICT (id) DO NOTHING"
        ).format(sql.Identifier(table), col_names, placeholders)
        
        inserted_count = 0
        for row in rows:
            values = []
            for col in columns:
                val = row[col]
                if isinstance(val, (dict, list)):
                    val = json.dumps(val)
                values.append(val)
                
            try:
                cur_neon.execute(insert_query, tuple(values))
                inserted_count += cur_neon.rowcount
            except Exception as e:
                print(f"   ❌ Error inserting row: {e}")
                conn_neon.rollback()
                continue
                
        conn_neon.commit()
        print(f"   ✅ Successfully inserted {inserted_count} NEW rows into {table}.")

    cur_local.close()
    conn_local.close()
    cur_neon.close()
    conn_neon.close()
    print("\n🎉 All Done!")

if __name__ == "__main__":
    sync()
