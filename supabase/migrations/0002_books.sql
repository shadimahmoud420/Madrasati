-- Official PDF books (Phase: library).
--
-- Books may now carry a PDF in Supabase Storage (bucket "books"), with the
-- semester they belong to and their size. Subjects that have PDF books are
-- published even before their lessons are ready, so every grade can get its
-- official books right away. Upload with tool/upload_books.py.

alter table books add column if not exists semester int check (semester in (1, 2));
alter table books add column if not exists size_bytes bigint;

-- Public, read-only bucket for the PDFs (writes need the service role).
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public)
    values ('books', 'books', true)
    on conflict (id) do update set public = true;
  end if;
end $$;

-- Assembles a grade's pack from the tables above and bumps its version.
create or replace function publish_pack(p_grade text) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_version int;
  v_pack jsonb;
begin
  -- Allowed from the SQL editor / service role, and for admin users.
  if auth.role() is not null and auth.role() <> 'service_role' and not is_admin() then
    raise exception 'admins only';
  end if;
  select coalesce(max(version), 0) + 1 into v_version from content_packs where grade_id = p_grade;

  select jsonb_build_object(
    'gradeId', p_grade,
    'version', v_version,
    'subjects', coalesce(jsonb_agg(s.obj order by s.sort), '[]'::jsonb)
  ) into v_pack
  from (
    select sub.sort, jsonb_build_object(
      'id', sub.id,
      'books', (
        select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', b.id, 'title', b.title, 'pdfUrl', b.pdf_url, 'semester', b.semester, 'sizeBytes', b.size_bytes,
          'pages', (select coalesce(jsonb_agg(jsonb_build_object(
              'number', bp.number, 'text', bp.text, 'lessonId', bp.lesson_id) order by bp.number), '[]'::jsonb)
            from book_pages bp where bp.book_id = b.id)
        )) order by b.semester nulls first, b.title), '[]'::jsonb)
        from books b where b.subject_id = sub.id
      ),
      'units', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', u.id, 'semester', u.semester, 'title', u.title,
          'lessons', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', l.id, 'unitId', u.id, 'title', l.title, 'objectives', to_jsonb(l.objectives),
              'explanation', l.explanation, 'examples', to_jsonb(l.examples),
              'keyPoints', to_jsonb(l.key_points), 'summary', l.summary,
              'videoUrl', l.video_url, 'bookPage', l.book_page,
              'questions', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                  'id', q.id, 'type', q.type, 'difficulty', q.difficulty, 'prompt', q.prompt,
                  'options', to_jsonb(q.options), 'answer', q.answer, 'accepted', to_jsonb(q.accepted),
                  'pairs', q.pairs, 'tolerance', q.tolerance, 'unit', q.unit,
                  'explanation', q.explanation, 'modelAnswer', q.model_answer, 'image', q.image
                )) order by q.sort), '[]'::jsonb)
                from questions q where q.lesson_id = l.id)
            ) order by l.sort), '[]'::jsonb)
            from lessons l where l.unit_id = u.id and l.published)
        ) order by u.semester, u.sort), '[]'::jsonb)
        from units u where u.subject_id = sub.id
      ),
      'exams', (
        select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', e.id, 'title', e.title, 'durationMinutes', e.duration_minutes,
          'questionCount', e.question_count, 'questionIds', to_jsonb(e.question_ids)
        ))), '[]'::jsonb)
        from exams e where e.subject_id = sub.id
      )
    ) as obj
    from subjects sub
    where sub.grade_id = p_grade
      and (exists (select 1 from units u join lessons l on l.unit_id = u.id
                   where u.subject_id = sub.id and l.published)
           or exists (select 1 from books b where b.subject_id = sub.id and b.pdf_url is not null))
  ) s;

  insert into content_packs (grade_id, version, pack, published_at)
  values (p_grade, v_version, v_pack, now())
  on conflict (grade_id) do update set version = excluded.version, pack = excluded.pack, published_at = now();
  return v_version;
end $$;

