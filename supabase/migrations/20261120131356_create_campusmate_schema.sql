create table public.courses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) > 0),
  exam_date timestamptz not null,
  difficulty smallint not null default 3 check (difficulty between 1 and 5),
  color text not null default 'blue'
    check (color in ('blue','green','orange','red','purple','teal')),
  icon text not null default 'book.fill',
  created_at timestamptz not null default now()
);

create table public.study_tasks (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null check (char_length(trim(title)) > 0),
  due_date timestamptz,
  estimated_minutes integer not null default 30 check (estimated_minutes > 0),
  is_completed boolean not null default false,
  created_at timestamptz not null default now()
);
create index study_tasks_course_id_idx on public.study_tasks(course_id);

create table public.study_plans (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  available_minutes integer not null check (available_minutes > 0),
  content text not null,
  source text not null check (source in ('ai','local')),
  created_at timestamptz not null default now()
);
create index study_plans_course_id_idx on public.study_plans(course_id);
