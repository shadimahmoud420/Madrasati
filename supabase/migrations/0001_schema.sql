-- Madrasati backend schema (Supabase / Postgres).
--
-- Content hierarchy: grades → subjects → units → lessons → questions,
-- with books (pages) and exams per subject. Editors change these tables
-- (Supabase Studio today, the admin dashboard later), then run
--   select publish_pack('g4');
-- which assembles the grade's JSON pack and bumps its version. Apps pull
-- new versions automatically — no app update needed.

-- ------------------------------------------------------------------ roles

create type user_role as enum ('student', 'parent', 'teacher', 'admin');

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  role user_role not null default 'student',
  display_name text,
  grade_id text,
  created_at timestamptz not null default now()
);

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

-- Every new auth user (including anonymous students) gets a profile.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------- content

create table grades (
  id text primary key,            -- g1 … g10, g11_sci, g11_lit, g12_sci, g12_lit
  number int not null check (number between 1 and 12),
  stage text not null check (stage in ('lowerBasic', 'upperBasic', 'secondary')),
  stream text,
  name text not null
);

create table subjects (
  id text primary key,            -- e.g. g4_math
  grade_id text not null references grades on delete cascade,
  key text not null,
  name text not null,
  icon text not null default 'menu_book',
  color bigint not null default 4279143278,
  sort int not null default 0
);

create table units (
  id text primary key,
  subject_id text not null references subjects on delete cascade,
  semester int not null default 1 check (semester in (1, 2)),
  title text not null,
  sort int not null default 0
);

create table lessons (
  id text primary key,
  unit_id text not null references units on delete cascade,
  title text not null,
  objectives text[] not null default '{}',
  explanation text not null default '',
  examples text[] not null default '{}',
  key_points text[] not null default '{}',
  summary text not null default '',
  video_url text,
  book_page int,
  sort int not null default 0,
  published boolean not null default false
);

create table questions (
  id text primary key,
  lesson_id text not null references lessons on delete cascade,
  type text not null check (type in ('mcq', 'trueFalse', 'fill', 'match', 'short', 'essay', 'numeric')),
  difficulty int not null default 1 check (difficulty between 1 and 4),
  prompt text not null,
  options text[],
  answer jsonb,                   -- mcq: index, trueFalse: bool, numeric: number
  accepted text[],                -- fill / short
  pairs jsonb,                    -- match: [["left","right"], …]
  tolerance double precision,
  unit text,
  explanation text,
  model_answer text,
  image text,
  sort int not null default 0
);

create table books (
  id text primary key,
  subject_id text not null references subjects on delete cascade,
  title text not null,
  pdf_url text
);

create table book_pages (
  book_id text not null references books on delete cascade,
  number int not null,
  text text not null,
  lesson_id text references lessons on delete set null,
  primary key (book_id, number)
);

create table exams (
  id text primary key,
  subject_id text not null references subjects on delete cascade,
  title text not null,
  duration_minutes int not null default 30,
  question_count int not null default 10,
  question_ids text[]             -- null: draw from the subject's bank
);

-- Published packs served to the apps (one row per grade).
create table content_packs (
  grade_id text primary key references grades on delete cascade,
  version int not null default 0,
  pack jsonb not null,
  published_at timestamptz not null default now()
);

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
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', b.id, 'title', b.title, 'pdfUrl', b.pdf_url,
          'pages', (select coalesce(jsonb_agg(jsonb_build_object(
              'number', bp.number, 'text', bp.text, 'lessonId', bp.lesson_id) order by bp.number), '[]'::jsonb)
            from book_pages bp where bp.book_id = b.id)
        )), '[]'::jsonb)
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
      and exists (select 1 from units u join lessons l on l.unit_id = u.id
                  where u.subject_id = sub.id and l.published)
  ) s;

  insert into content_packs (grade_id, version, pack, published_at)
  values (p_grade, v_version, v_pack, now())
  on conflict (grade_id) do update set version = excluded.version, pack = excluded.pack, published_at = now();
  return v_version;
end $$;

-- --------------------------------------------------------------- activity

create table attempts (
  id bigint generated always as identity primary key,
  uid uuid not null unique,                         -- generated on the device; makes retries idempotent
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  grade_id text,
  kind text not null,
  title text not null,
  subject_id text,
  lesson_id text,
  exam_id text,
  started_at timestamptz not null,
  duration_sec int not null,
  score double precision not null,
  max_score double precision not null,
  received_at timestamptz not null default now()
);
create index attempts_user on attempts (user_id, started_at desc);

-- Phase 2: parents and teachers (tables ready; app screens come later).
create table parent_links (
  parent_id uuid not null references auth.users on delete cascade,
  student_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);

create table classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users on delete cascade,
  grade_id text references grades,
  name text not null,
  join_code text not null unique default substr(md5(random()::text), 1, 6)
);

create table class_members (
  class_id uuid not null references classes on delete cascade,
  student_id uuid not null references auth.users on delete cascade,
  primary key (class_id, student_id)
);

-- Per-user daily counter for the AI tutor (written by the Edge Function).
create table tutor_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null default current_date,
  count int not null default 0,
  primary key (user_id, day)
);

-- --------------------------------------------------------------- security

alter table profiles enable row level security;
alter table grades enable row level security;
alter table subjects enable row level security;
alter table units enable row level security;
alter table lessons enable row level security;
alter table questions enable row level security;
alter table books enable row level security;
alter table book_pages enable row level security;
alter table exams enable row level security;
alter table content_packs enable row level security;
alter table attempts enable row level security;
alter table parent_links enable row level security;
alter table classes enable row level security;
alter table class_members enable row level security;
alter table tutor_usage enable row level security;

create policy "own profile" on profiles for select using (id = auth.uid() or is_admin());
create policy "update own profile" on profiles for update using (id = auth.uid())
  with check (id = auth.uid() and role = (select role from profiles where id = auth.uid()));
create policy "admin profiles" on profiles for all using (is_admin()) with check (is_admin());

-- Content: readable by everyone (also served via the content function),
-- writable by admins only.
do $$
declare t text;
begin
  foreach t in array array['grades','subjects','units','lessons','questions','books','book_pages','exams','content_packs'] loop
    execute format('create policy "read %1$s" on %1$I for select using (true)', t);
    execute format('create policy "admin write %1$s" on %1$I for all using (is_admin()) with check (is_admin())', t);
  end loop;
end $$;

-- Students see only their own results; linked parents and their teachers
-- can read them; nobody else.
create policy "insert own attempts" on attempts for insert with check (user_id = auth.uid());
create policy "read own attempts" on attempts for select using (
  user_id = auth.uid()
  or is_admin()
  or exists (select 1 from parent_links p where p.parent_id = auth.uid() and p.student_id = attempts.user_id)
  or exists (select 1 from class_members m join classes c on c.id = m.class_id
             where m.student_id = attempts.user_id and c.teacher_id = auth.uid())
);

create policy "parent links" on parent_links for select using (parent_id = auth.uid() or student_id = auth.uid() or is_admin());
create policy "teacher classes" on classes for all using (teacher_id = auth.uid() or is_admin())
  with check (teacher_id = auth.uid() or is_admin());
create policy "class members" on class_members for select using (
  student_id = auth.uid() or is_admin()
  or exists (select 1 from classes c where c.id = class_id and c.teacher_id = auth.uid())
);
-- tutor_usage: no policies → only the service role (Edge Function) can touch it.
