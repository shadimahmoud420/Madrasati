# الكتب المرفقة داخل التطبيق

ضع هنا الكتب الرسمية بصيغة PDF لتكون داخل التطبيق نفسه (بدون أي تحميل):

    assets/books/<الصف>/<المادة>/<الفصل>/<اسم الكتاب>.pdf

- الصف: g1 … g10، g11_sci، g11_lit، g12_sci، g12_lit
- المادة: arabic، math، science، islamic، english، national، social، tech، physics، chemistry، biology، geography، history
- الفصل: s1 أو s2 أو all (كتاب السنة كاملة)

مثال: `assets/books/g5/arabic/s1/لغتنا الجميلة - الجزء الأول.pdf`

ثم شغّل `python3 tool/build_content.py` (أو `bash tool/setup.sh`) ليُسجَّل الكتاب في التطبيق.
انتبه: كل كتاب يزيد حجم التطبيق بحجمه.
