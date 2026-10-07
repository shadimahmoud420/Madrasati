"""Uploads official PDF books to Supabase and publishes them to the apps.

Put the PDFs in a folder laid out as  <grade>/<subject>/<semester>/<title>.pdf

    books/
      g4/
        math/
          s1/الرياضيات - الجزء الأول.pdf
          s2/الرياضيات - الجزء الثاني.pdf
        arabic/
          s1/لغتنا الجميلة - الجزء الأول.pdf
      g12_sci/
        physics/
          all/الفيزياء.pdf            ← "all" = whole year

  <grade>    a grade id from assets/content/catalog.json (g1 … g10, g11_sci,
             g11_lit, g12_sci, g12_lit)
  <subject>  a subject key: arabic, math, science, islamic, english, national,
             social, tech, physics, chemistry, biology, geography, history
  <semester> s1, s2 or all
  file name  becomes the book title shown to students

Then run (the service role key is in Supabase → Project Settings → API):

    export SUPABASE_URL=https://<ref>.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...
    python3 tool/upload_books.py books/            # upload + publish
    python3 tool/upload_books.py books/ --dry-run  # only check the folder

Re-running is safe: unchanged files are skipped, changed files replace the
old ones, and each affected grade is re-published so apps download it.
Only standard-library Python 3 is needed.
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
CATALOG = os.path.join(ROOT, "assets", "content", "catalog.json")
SEMESTERS = {"s1": 1, "s2": 2, "all": None}
BUCKET = "books"


def load_catalog():
    with open(CATALOG, encoding="utf-8") as f:
        cat = json.load(f)
    return {g["id"]: {s["key"]: s["id"] for s in g["subjects"]} for g in cat["grades"]}


def scan(folder, catalog):
    """Returns (books, problems). Each book is a dict ready to upload."""
    books, problems = [], []
    for dirpath, _, files in os.walk(folder):
        for name in sorted(files):
            if name.startswith("."):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, folder)
            parts = rel.split(os.sep)
            if not name.lower().endswith(".pdf"):
                problems.append(f"ليس PDF، تم تجاهله: {rel}")
                continue
            if len(parts) != 4:
                problems.append(f"المسار يجب أن يكون <الصف>/<المادة>/<الفصل>/<الكتاب>.pdf: {rel}")
                continue
            grade, subject, semester, _ = parts
            if grade not in catalog:
                problems.append(f"صف غير معروف «{grade}»: {rel}")
                continue
            if subject not in catalog[grade]:
                problems.append(f"المادة «{subject}» غير موجودة في {grade} (المتاح: {', '.join(catalog[grade])}): {rel}")
                continue
            if semester not in SEMESTERS:
                problems.append(f"الفصل يجب أن يكون s1 أو s2 أو all: {rel}")
                continue
            with open(path, "rb") as f:
                data = f.read()
            if not data.startswith(b"%PDF-"):
                problems.append(f"الملف تالف أو ليس PDF حقيقيًا: {rel}")
                continue
            digest = hashlib.sha256(data).hexdigest()
            key = hashlib.sha1(rel.encode("utf-8")).hexdigest()[:10]
            books.append({
                "path": path,
                "grade": grade,
                "id": f"{grade}_{subject}_{semester}_{key}",
                "subject_id": catalog[grade][subject],
                "semester": SEMESTERS[semester],
                "title": os.path.splitext(name)[0].strip(),
                "size_bytes": len(data),
                # Content hash in the object name: a changed file gets a new
                # URL, so apps never keep a stale copy.
                "object": f"{grade}/{subject}/{semester}/{key}-{digest[:12]}.pdf",
                "data": data,
            })
    return books, problems


class Supabase:
    def __init__(self, url, key):
        self.url = url.rstrip("/")
        self.key = key

    def _request(self, method, path, body=None, headers=None, content_type="application/json"):
        req = urllib.request.Request(self.url + path, data=body, method=method)
        req.add_header("apikey", self.key)
        req.add_header("Authorization", f"Bearer {self.key}")
        if body is not None:
            req.add_header("Content-Type", content_type)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise SystemExit(f"خطأ من الخادم ({e.code}) في {path}: {e.read().decode('utf-8', 'replace')}")

    def existing_books(self):
        rows = self._request("GET", "/rest/v1/books?select=id,pdf_url,size_bytes")
        return {r["id"]: r for r in rows or []}

    def upload(self, obj, data):
        self._request(
            "POST", f"/storage/v1/object/{BUCKET}/{obj}", data,
            headers={"x-upsert": "true"}, content_type="application/pdf",
        )
        return f"{self.url}/storage/v1/object/public/{BUCKET}/{obj}"

    def upsert_book(self, row):
        self._request(
            "POST", "/rest/v1/books?on_conflict=id", json.dumps(row).encode("utf-8"),
            headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
        )

    def publish(self, grade):
        return self._request("POST", "/rest/v1/rpc/publish_pack", json.dumps({"p_grade": grade}).encode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description="Upload official PDF books to Supabase.")
    parser.add_argument("folder")
    parser.add_argument("--dry-run", action="store_true", help="check the folder without uploading")
    args = parser.parse_args()

    books, problems = scan(args.folder, load_catalog())
    for p in problems:
        print("⚠️ ", p)
    total = sum(b["size_bytes"] for b in books)
    print(f"وُجد {len(books)} كتابًا ({total / 1024 / 1024:.1f} م.ب) في {len({b['grade'] for b in books})} صفوف.")
    if args.dry_run or not books:
        for b in books:
            sem = {1: "الفصل الأول", 2: "الفصل الثاني", None: "كامل السنة"}[b["semester"]]
            print(f"  • {b['grade']} / {b['subject_id']} / {sem}: {b['title']}")
        return 1 if problems else 0

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        sys.exit("ضع SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY في متغيرات البيئة أولًا.")
    sb = Supabase(url, key)
    existing = sb.existing_books()
    changed_grades = set()
    for b in books:
        public_url = f"{sb.url}/storage/v1/object/public/{BUCKET}/{b['object']}"
        old = existing.get(b["id"])
        if old and old.get("pdf_url") == public_url:
            print(f"  = بلا تغيير: {b['title']}")
            continue
        print(f"  ↑ رفع: {b['title']} ({b['size_bytes'] / 1024 / 1024:.1f} م.ب)")
        sb.upload(b["object"], b["data"])
        sb.upsert_book({
            "id": b["id"],
            "subject_id": b["subject_id"],
            "title": b["title"],
            "semester": b["semester"],
            "size_bytes": b["size_bytes"],
            "pdf_url": public_url,
        })
        changed_grades.add(b["grade"])
    for grade in sorted(changed_grades):
        version = sb.publish(grade)
        print(f"✓ نُشر {grade} (الإصدار {version}) — ستحمّله التطبيقات عند اتصالها.")
    if not changed_grades:
        print("لا يوجد جديد للنشر.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
