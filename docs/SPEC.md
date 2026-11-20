# CampusMate — specifikacija (SPEC.md)

iOS aplikacija za studente: predmeti, zadaci za učenje, procena spremnosti, dnevni plan i AI plan učenja.
Swift + SwiftUI, MVVM, Supabase (PostgreSQL).

**Kako se čita ovaj fajl:** agent na početku svake sesije čita sekcije 1–5 i **samo slice na kom se radi**. Ostale slice-ove ne čita i ne implementira unapred.

---

## 1. Pravila rada za agenta

Cilj projekta nije samo aplikacija koja radi, već da student razume svaki fajl i može sam da ga izmeni pred profesorom. Zato:

1. Radi **tačno jedan slice** po sesiji. Ne diraj fajlove van liste „Fajlovi” osim ako je neophodno, i tada prvo reci zašto.
2. Pre pisanja koda napiši plan u 3–5 rečenica: koje fajlove praviš i šta svaki radi.
3. Kod mora biti juniorski čitljiv: bez generičkih apstrakcija, bez dodatnih biblioteka (dozvoljen je samo `supabase-swift`), bez „pametnih” trikova. Fajl duži od ~150 linija je znak da treba podeliti View.
4. Kratak komentar stavi samo iznad linija koje nisu očigledne početniku (`async let`, `CodingKeys`, `@Bindable`…).
5. Kada završiš, napiši:
   - šta svaki novi/izmenjeni fajl radi (1–2 rečenice po fajlu),
   - koje nove Swift/SwiftUI koncepte je slice uveo,
   - 3 kontrolna pitanja za studenta (bez odgovora dok ih student ne zatraži).
6. Ne radi sekciju „Vežba” — nju student radi ručno. Ako student traži pomoć oko vežbe, daj nagoveštaj, a ne gotov kod.
7. Slice je gotov tek kada student potvrdi korake iz „Provera”. Tada označi slice u tabeli u sekciji 6 i predloži commit: `slice-N: kratak opis`.
8. Za Supabase SDK ne oslanjaj se na pamćenje: pre prvog korišćenja neke funkcije (`from().select()`, `functions.invoke`…) proveri aktuelnu dokumentaciju `supabase-swift` v2.
9. Bazu menjaj isključivo kroz Supabase MCP migracije (npr. `apply_migration`), a proveravaj upitima (npr. `execute_sql`). Nikad ne menjaj šemu ručno „usput” u drugom slice-u.

**Šablon poruke za početak sesije:**

> Pročitaj SPEC.md sekcije 1–5 i Slice N. Implementiraj samo Slice N po pravilima iz sekcije 1. Prvo mi napiši plan, pa sačekaj moju potvrdu.

---

## 2. Odluke i pretpostavke

| Tema | Odluka | Zašto |
|---|---|---|
| Minimalni iOS | iOS 17.0 | Zbog `@Observable`. |
| Stanje u ViewModel-u | `@Observable` klasa + `@State` u View-u | Moderniji i kraći pristup. **Ako je profesor radio `ObservableObject` / `@Published` / `@StateObject`, reci agentu pre Slice 4 da koristi to.** |
| Prijava korisnika | Nema (jedan korisnik) | Da aplikacija ostane jednostavna. Posledica: RLS politike su otvorene za `anon` ulogu, pa svako ko ima ključ može da čita/piše. Prihvatljivo za ispitni projekat, nije za javnu objavu. |
| Jezik | Kod i baza na engleskom, tekst u interfejsu na srpskom (latinica) | |
| Datumi u bazi | Sve kolone su `timestamptz` | Podrazumevani dekoder iz SDK-a ih čita bez dodatnog koda. |
| `id` zapisa | `UUID()` se pravi u Swift-u pri kreiranju | Isti `struct` služi za čitanje, upis i izmenu, bez posebnih DTO tipova. |
| Osvežavanje podataka | Svaki ekran učitava podatke u `.task` i ima `.refreshable` | Nema deljenog globalnog stanja; lako se objašnjava. |
| AI poziv | Supabase Edge Function, API ključ je u Supabase secrets | AI ključ nikad ne sme da bude u iOS aplikaciji. |
| AI provajder | Po izboru studenta (odlučuje se u Slice 16) | |
| Testovi | Unit testovi (XCTest) samo za čistu logiku u `Logic/` | To je deo koji je najlakše testirati i objasniti. |

Van opsega cele aplikacije: prijava/registracija, notifikacije, offline keš, widget, iPad raspored.

---

## 3. Arhitektura

### Slojevi (MVVM)

```
View  →  ViewModel  →  Service  →  Supabase
                   ↘  Logic (čiste funkcije, bez mreže i bez SwiftUI)
```

- **Model** — `struct`, `Codable`, `Identifiable`. Samo podaci.
- **Service** — `struct` sa `async throws` funkcijama. Jedino mesto gde se pominje Supabase.
- **Logic** — `enum`/`struct` sa statičkim funkcijama. Ne uvozi ni SwiftUI ni Supabase. Dobija `now: Date` kao parametar da bi se moglo testirati.
- **ViewModel** — `@MainActor @Observable final class`. Drži stanje ekrana, zove servise i logiku. Ne uvozi SwiftUI.
- **View** — samo prikaz i prosleđivanje akcija ViewModel-u. Ne zove servise direktno.

### Struktura foldera

```
CampusMate/
  App/          CampusMateApp.swift, RootTabView.swift
  Config/       Secrets.swift (u .gitignore), Secrets.example.swift
  Models/       Course.swift, StudyTask.swift, StudyPlan.swift
  Services/     SupabaseManager.swift, CourseService.swift, StudyTaskService.swift,
                StudyPlanService.swift, PlanGenerating.swift, AIPlanGenerator.swift
  Logic/        Date+Days.swift, ReadinessCalculator.swift, DailyPlanner.swift,
                LocalPlanGenerator.swift
  ViewModels/   po jedan ViewModel za svaki ekran
  Views/        Dashboard/, Courses/, Tasks/, DailyPlan/, AIPlanner/, Components/
CampusMateTests/
supabase/functions/generate-study-plan/index.ts
```

### Obrazac za ViewModel (svi ekrani ga prate)

```swift
@MainActor
@Observable
final class CoursesViewModel {
    var courses: [Course] = []
    var isLoading = false
    var errorMessage: String?

    private let service = CourseService()

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            courses = try await service.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = "Učitavanje nije uspelo. Pokušaj ponovo."
        }
    }
}
```

View: `@State private var viewModel = CoursesViewModel()`, zatim `.task { await viewModel.load() }` i `.refreshable { await viewModel.load() }`.

### Ekrani i navigacija

`TabView` sa 5 tabova; šesti ekran (Detalj predmeta) se otvara iz liste predmeta.

| Tab | Ekran | SF Symbol |
|---|---|---|
| Početna | Dashboard | `house.fill` |
| Predmeti | Lista predmeta → Detalj predmeta | `books.vertical.fill` |
| Zadaci | Zadaci za učenje | `checklist` |
| Danas | Dnevni plan | `calendar` |
| AI plan | AI planiranje | `sparkles` |

---

## 4. Model podataka

### Tabele

**courses**

| Kolona | Tip | Napomena |
|---|---|---|
| id | uuid, PK | |
| name | text, not null | ne sme biti prazan |
| exam_date | timestamptz, not null | |
| difficulty | smallint, not null, default 3 | 1–5 |
| color | text, not null, default 'blue' | blue, green, orange, red, purple, teal |
| icon | text, not null, default 'book.fill' | naziv SF Symbol-a |
| created_at | timestamptz, default now() | ne koristi se u Swift modelu |

**study_tasks**

| Kolona | Tip | Napomena |
|---|---|---|
| id | uuid, PK | |
| course_id | uuid, FK → courses.id, on delete cascade | |
| title | text, not null | |
| due_date | timestamptz, null | rok je opcion |
| estimated_minutes | integer, not null, default 30 | > 0 |
| is_completed | boolean, not null, default false | |
| created_at | timestamptz, default now() | |

**study_plans**

| Kolona | Tip | Napomena |
|---|---|---|
| id | uuid, PK | |
| course_id | uuid, FK → courses.id, on delete cascade | |
| available_minutes | integer, not null | > 0 |
| content | text, not null | tekst plana |
| source | text, not null | 'ai' ili 'local' |
| created_at | timestamptz, default now() | |

### Swift modeli

```swift
enum CourseColor: String, Codable, CaseIterable { case blue, green, orange, red, purple, teal }

struct Course: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var examDate: Date
    var difficulty: Int
    var color: CourseColor
    var icon: String
}

struct StudyTask: Identifiable, Codable, Hashable {
    let id: UUID
    var courseId: UUID
    var title: String
    var dueDate: Date?
    var estimatedMinutes: Int
    var isCompleted: Bool
}

struct StudyPlan: Identifiable, Codable, Hashable {
    let id: UUID
    var courseId: UUID
    var availableMinutes: Int
    var content: String
    var source: PlanSource      // enum PlanSource: String, Codable { case ai, local }
    var createdAt: Date
}
```

Mapiranje `snake_case` ↔ `camelCase` radi se **ručno preko `CodingKeys`** u svakom modelu (namerno, da se vidi kako `Codable` radi).

---

## 5. Poslovna logika (tačne formule)

Sve funkcije su čiste: isti ulaz daje isti izlaz, `now` se prosleđuje kao parametar.

### 5.1 Dani do datuma — `Date+Days.swift`

`daysUntil(_ date: Date, from now: Date) -> Int` = razlika u **kalendarskim danima** između početka dana `now` i početka dana `date` (`Calendar.current.startOfDay`). Danas = 0, sutra = 1, juče = −1.

### 5.2 Spremnost — `ReadinessCalculator`

- `total` = zbir `estimatedMinutes` svih zadataka predmeta
- `done` = zbir `estimatedMinutes` završenih zadataka
- **`score(tasks:) -> Int`** = `total == 0 ? 0 : zaokruženo(done / total × 100)`
- **`pace(tasks:examDate:now:) -> Pace`**:
  - `remaining = total − done`
  - `perDay = remaining / max(daysUntil(examDate), 1)`
  - `total == 0` → `.noTasks` („Dodaj zadatke”, sivo)
  - `remaining == 0` → `.ready` („Spreman”, zeleno)
  - `perDay ≤ 60` → `.onTrack` („Na dobrom putu”, zeleno)
  - `perDay ≤ 120` → `.behind` („Pojačaj tempo”, narandžasto)
  - inače → `.critical` („Kritično”, crveno)

### 5.3 Dnevni plan — `DailyPlanner`

Ulaz: svi zadaci, svi predmeti, `budgetMinutes`, `now`.

1. Uzmi samo nezavršene zadatke čiji predmet postoji i čiji ispit nije prošao (`daysUntil(examDate) ≥ 0`).
2. Za svaki zadatak: `deadline = min(dueDate ?? examDate, examDate)`, `daysLeft = daysUntil(deadline)`.
3. **Prioritet:** ako je `daysLeft < 0` (rok zadatka prošao) → `1000`; inače `difficulty × 10 / (daysLeft + 1)`.
   Primer: težina 5, rok za 2 dana → 16.7; težina 2, rok za 9 dana → 2.0.
4. Sortiraj po prioritetu opadajuće; kod istog prioriteta prvo kraći zadatak.
5. Pohlepno biraj: dodaj zadatak ako `iskorišćeno + estimatedMinutes ≤ budgetMinutes`, inače ga preskoči i probaj sledeći.
6. Ako nijedan zadatak ne staje u budžet, a lista nije prazna, vrati samo prvi (najprioritetniji).

Izlaz: `[PlannedTask]` gde je `PlannedTask { task, course, priority }`.

### 5.4 Lokalni plan učenja — `LocalPlanGenerator`

Ulaz: `PlanRequest { courseName, difficulty, daysUntilExam, availableMinutes, openTasks: [title, estimatedMinutes] }`.

- Ako ima otvorenih zadataka: uzmi ih redom dok staju u `availableMinutes` i vrati tekst:
  `Do ispita iz <predmet>: <N> dana. Danas (<M> min):` pa numerisana lista `1. <naslov> (<min> min)`.
  Ako ostane ≥ 15 minuta, dodaj stavku `Ponavljanje gradiva (<ostatak> min)`.
- Ako nema zadataka: podeli vreme 70% „Novo gradivo” / 30% „Zadaci i ponavljanje”.
- Ako je `daysUntilExam ≤ 2`, dodaj na kraj rečenicu: `Ispit je blizu — fokus na ponavljanje i stare rokove.`

---

## 6. Napredak

| # | Slice | Gotovo |
|---|---|---|
| 0 | Skelet projekta i tabovi | ☐ |
| 1 | Baza: šema | ☐ |
| 2 | Baza: RLS politike i test podaci | ☐ |
| 3 | Supabase klijent, model `Course`, `CourseService` | ☐ |
| 4 | Lista predmeta (prvi MVVM ekran) | ☐ |
| 5 | Dodavanje predmeta | ☐ |
| 6 | Izmena i brisanje predmeta | ☐ |
| 7 | Detalj predmeta i odbrojavanje | ☐ |
| 8 | Lista zadataka i označavanje | ☐ |
| 9 | Dodavanje, izmena i brisanje zadatka | ☐ |
| 10 | Zadaci u detalju predmeta | ☐ |
| 11 | Procena spremnosti | ☐ |
| 12 | `DailyPlanner` logika | ☐ |
| 13 | Ekran Dnevni plan | ☐ |
| 14 | Dashboard | ☐ |
| 15 | AI planiranje: ekran + lokalni generator | ☐ |
| 16 | Edge Function + AI generator + fallback | ☐ |
| 17 | Čuvanje planova i istorija | ☐ |
| 18 | Doterivanje i priprema za odbranu | ☐ |

---

## 7. Slice-ovi

### Slice 0 — Skelet projekta i tabovi

**Cilj:** aplikacija se pokreće i ima 5 praznih tabova.

**Ručno (student, pre agenta):** u Xcode-u napravi projekat *App* → naziv `CampusMate`, Interface: SwiftUI, uključi testove, deployment target iOS 17.0. Dodaj paket `https://github.com/supabase/supabase-swift.git` (verzija 2.x, proizvod `Supabase`). Pokreni `git init`.

**Fajlovi:** `App/RootTabView.swift`, po jedan prazan View u `Views/<Ekran>/` (`DashboardView`, `CoursesView`, `TasksView`, `DailyPlanView`, `AIPlannerView`), folderi iz sekcije 3, `.gitignore`.

**Zahtevi:**
- `RootTabView` sa 5 tabova (nazivi i ikone iz sekcije 3), koristi `.tabItem`.
- Svaki ekran je `NavigationStack` sa naslovom i tekstom „Uskoro”.
- `.gitignore` sadrži `Config/Secrets.swift`.

**Provera:** aplikacija se pokreće u simulatoru; svih 5 tabova se otvara i ima ispravan naslov.

**Koncepti:** `@main` i `App` protokol, `View` i `body`, `TabView`, `NavigationStack`, `#Preview`.

**Vežba:** promeni redosled dva taba i ikonu jednog. Dodaj privremeno šesti tab i pogledaj šta iOS uradi.

---

### Slice 1 — Baza: šema

**Cilj:** tri tabele postoje u Supabase-u sa svim ograničenjima.

**Zahtevi:** kroz MCP primeni jednu migraciju `create_campusmate_schema`:

```sql
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
```

**Van opsega:** RLS, test podaci, bilo kakav Swift kod.

**Provera:**
- U Supabase Table Editor-u se vide sve tri tabele sa kolonama iz sekcije 4.
- Agent upitom pokaže da `insert` sa `difficulty = 9` i `insert` zadatka sa nepostojećim `course_id` **ne prolaze**.

**Koncepti:** primarni i strani ključ, `on delete cascade`, `check` ograničenja, `default`, migracija.

**Vežba:** objasni naglas šta se desi sa zadacima kada se obriše predmet i gde je to u SQL-u definisano.

---

### Slice 2 — Baza: RLS politike i test podaci

**Cilj:** aplikacija sme da čita/piše tabele javnim ključem, a u bazi postoje podaci za testiranje.

**Zahtevi:**
- Migracija `enable_rls_open_policies`: za sve tri tabele `enable row level security` i po jedna politika:
  `create policy "<tabela>_open" on public.<tabela> for all to anon, authenticated using (true) with check (true);`
- Test podaci (obična SQL naredba, ne migracija), sa datumima **relativnim u odnosu na `now()`** da uvek budu u budućnosti:
  - 3 predmeta: „Baze podataka” (ispit za 6 dana, težina 4, blue, `book.fill`), „Matematika 2” (za 15 dana, težina 5, red, `function`), „Web programiranje” (za 30 dana, težina 2, green, `laptopcomputer`).
  - 8 zadataka raspoređenih po predmetima: različito `estimated_minutes` (20–90), 3 završena, 2 bez roka, 1 sa rokom u prošlosti (juče).

**Provera:**
- `select count(*)` vraća 3 predmeta i 8 zadataka.
- Agent u transakciji (sa `rollback`) pokaže da brisanje predmeta briše i njegove zadatke.
- Agent pokrene bezbednosnu proveru projekta (advisors) ako je dostupna i objasni upozorenja; upozorenje o otvorenim politikama je očekivano (sekcija 2).

**Koncepti:** Row Level Security, uloga `anon`, razlika između `using` i `with check`.

**Vežba:** svojim rečima objasni zašto bi ovakve politike bile problem u javnoj aplikaciji i šta bi se promenilo da postoji prijava korisnika.

---

### Slice 3 — Supabase klijent, model `Course`, `CourseService`

**Cilj:** aplikacija ume da pročita predmete iz baze (bez pravog ekrana).

**Fajlovi:** `Config/Secrets.swift`, `Config/Secrets.example.swift`, `Services/SupabaseManager.swift`, `Models/Course.swift`, `Services/CourseService.swift`, privremena izmena `CoursesView.swift`.

**Zahtevi:**
- `Secrets` je `enum` sa `static let supabaseURL` i `static let supabaseKey` (javni publishable/anon ključ). Student sam upisuje vrednosti; agent ih ne traži u četu.
- `SupabaseManager.client` — jedna deljena instanca `SupabaseClient`.
- `Course` i `CourseColor` po sekciji 4, sa ručnim `CodingKeys`.
- `CourseService.fetchAll() async throws -> [Course]`, sortirano po `exam_date` rastuće.
- Privremeno: `CoursesView` u `.task` pozove servis i prikaže `Text("Učitano predmeta: N")` ili tekst greške.

**Van opsega:** ViewModel, lista, upis u bazu.

**Provera:** tab Predmeti prikazuje „Učitano predmeta: 3”. Sa pogrešnim ključem u `Secrets` prikazuje se poruka o grešci, a aplikacija se ne ruši.

**Koncepti:** `struct`, `Codable` i `CodingKeys`, `enum` sa `rawValue`, `async/await`, `throws` i `do/catch`, `.task`.

**Vežba:** namerno pogreši jedan `CodingKeys` naziv (npr. `"examdate"`), pokreni aplikaciju i pročitaj grešku u konzoli. Vrati nazad.

---

### Slice 4 — Lista predmeta (prvi MVVM ekran)

**Cilj:** tab Predmeti prikazuje listu predmeta iz baze.

**Fajlovi:** `ViewModels/CoursesViewModel.swift`, `Views/Courses/CoursesView.swift`, `Views/Courses/CourseRow.swift`, `CourseColor` proširenje za SwiftUI boju (u `Views/Components/`).

**Zahtevi:**
- ViewModel po obrascu iz sekcije 3 (`courses`, `isLoading`, `errorMessage`, `load()`).
- `CourseRow`: ikona u boji predmeta, naziv, datum ispita (format `d. MMM yyyy.`), težina kao tekst „Težina 4/5”.
- Stanja ekrana: učitavanje (`ProgressView`), greška (poruka + dugme „Pokušaj ponovo”), prazno (`ContentUnavailableView` „Nema predmeta”), lista.
- `.refreshable` ponovo učitava.
- Ukloni privremeni kod iz Slice 3.

**Provera:** vide se 3 predmeta sortirana po datumu ispita; povlačenje nadole osvežava; izmena naziva u Supabase Table Editor-u se vidi nakon osvežavanja.

**Koncepti:** MVVM podela, `@Observable`, `@State`, `List` i `ForEach`, `Identifiable`, uslovno prikazivanje View-a.

**Vežba:** sortiraj listu po nazivu umesto po datumu (na dva načina: u servisu i u ViewModel-u). Prikaži težinu kao zvezdice umesto teksta.

---

### Slice 5 — Dodavanje predmeta

**Cilj:** dugme „+” otvara formu i novi predmet se pojavljuje u listi i u bazi.

**Fajlovi:** `Views/Courses/CourseFormView.swift`, `ViewModels/CourseFormViewModel.swift`, izmene u `CourseService` (`insert`) i `CoursesView` (toolbar dugme + `.sheet`).

**Zahtevi:**
- `Form` sa poljima: `TextField` naziv, `DatePicker` datum ispita (samo datum, od danas nadalje), `Stepper` težina 1–5, `Picker` boja (`CourseColor.allCases`), `Picker` ikona (lista: `book.fill`, `laptopcomputer`, `function`, `chart.bar.fill`, `globe`, `pencil`, `flask.fill`, `hammer.fill`).
- „Sačuvaj” je onemogućeno dok je naziv prazan (posle `trim`). „Otkaži” zatvara formu.
- Tokom čuvanja dugme je onemogućeno; greška se prikazuje u formi, a forma ostaje otvorena.
- Posle uspešnog čuvanja forma se zatvara i lista se ponovo učitava.

**Van opsega:** izmena postojećeg predmeta.

**Provera:** dodaj predmet → vidi se u listi na pravom mestu po datumu i u Table Editor-u. Prazan naziv ne može da se sačuva.

**Koncepti:** `Form`, `TextField`, `DatePicker`, `Stepper`, `Picker`, `@Binding`/`@Bindable`, `.sheet`, `@Environment(\.dismiss)`, validacija unosa.

**Vežba:** promeni validaciju tako da naziv mora imati bar 3 karaktera i prikaži poruku ispod polja kada uslov nije ispunjen.

---

### Slice 6 — Izmena i brisanje predmeta

**Cilj:** predmet može da se izmeni i obriše iz liste.

**Fajlovi:** izmene u `CourseService` (`update`, `delete`), `CourseFormViewModel` (režim izmene), `CourseFormView`, `CoursesView`, `CoursesViewModel`.

**Zahtevi:**
- Ista forma radi u dva režima: novi predmet (`course == nil`) i izmena (polja popunjena postojećim vrednostima, naslov „Izmeni predmet”).
- Prevlačenje ulevo na redu: „Izmeni” i „Obriši”.
- Brisanje traži potvrdu (`confirmationDialog`) sa upozorenjem da se brišu i zadaci predmeta.
- Ako brisanje ne uspe, predmet ostaje u listi i prikazuje se greška.

**Provera:** izmeni naziv i težinu → promena je u listi i u bazi. Obriši test predmet → nestaje iz liste, a njegovi zadaci iz tabele `study_tasks`.

**Koncepti:** `swipeActions`, `confirmationDialog`, opcioni tipovi (`Course?`) i `if let`, ponovna upotreba View-a.

**Vežba:** dodaj i dugme „Izmeni” u `contextMenu` (dugi pritisak na red).

---

### Slice 7 — Detalj predmeta i odbrojavanje

**Cilj:** dodir na predmet otvara ekran sa detaljima i odbrojavanjem do ispita.

**Fajlovi:** `Logic/Date+Days.swift`, `Views/Courses/CourseDetailView.swift`, `ViewModels/CourseDetailViewModel.swift`, izmena `CoursesView` (`NavigationLink(value:)` + `navigationDestination`), test `CampusMateTests/DateDaysTests.swift`.

**Zahtevi:**
- `daysUntil` po sekciji 5.1, sa unit testovima: danas, sutra, juče, datum u 23:59 istog dana.
- Zaglavlje: ikona, naziv, datum ispita, težina.
- Odbrojavanje: „Ispit je danas”, „Ispit je sutra”, „Još N dana”, a za prošli datum „Ispit je prošao”.
- Sekcije „Spremnost” i „Zadaci” postoje kao naslovi sa tekstom „Uskoro” (pune se u Slice 10 i 11).

**Provera:** otvori sva tri predmeta — broj dana odgovara datumima; testovi prolaze (⌘U).

**Koncepti:** `NavigationLink(value:)`, `navigationDestination(for:)`, `Hashable`, `Calendar`, `extension`, prvi unit test.

**Vežba:** dodaj tekst „Još nedelju dana” kada je tačno 7 dana do ispita i napiši test za to.

---

### Slice 8 — Lista zadataka i označavanje

**Cilj:** tab Zadaci prikazuje sve zadatke i omogućava da se označe kao završeni.

**Fajlovi:** `Models/StudyTask.swift`, `Services/StudyTaskService.swift` (`fetchAll`, `setCompleted`), `ViewModels/TasksViewModel.swift`, `Views/Tasks/TasksView.swift`, `Views/Tasks/TaskRow.swift`.

**Zahtevi:**
- ViewModel učitava zadatke i predmete **paralelno** (`async let`) da bi red prikazao naziv i boju predmeta.
- `TaskRow`: krug za štikliranje, naslov (precrtan ako je završen), naziv predmeta, procenjeno vreme, rok ako postoji (crveno ako je prošao a zadatak nije završen).
- Dodir na krug menja `is_completed` u bazi. Izmena se odmah vidi; ako upis ne uspe, vrednost se vraća i prikazuje se greška.
- Dve sekcije: „Za rad” i „Završeno”. `Toggle` „Sakrij završene” na vrhu.

**Van opsega:** dodavanje, izmena i brisanje zadataka.

**Provera:** vidi se 8 test zadataka; štikliranje premešta zadatak u drugu sekciju i menja vrednost u bazi; `Toggle` sakriva sekciju „Završeno”.

**Koncepti:** `async let`, `Toggle`, `Section`, izračunata svojstva (`var openTasks: [StudyTask]`), `filter`, optimistično ažuriranje.

**Vežba:** dodaj u naslov sekcije broj zadataka, npr. „Za rad (5)”. Sortiraj otvorene zadatke po roku, sa zadacima bez roka na kraju.

---

### Slice 9 — Dodavanje, izmena i brisanje zadatka

**Cilj:** potpun CRUD nad zadacima iz taba Zadaci.

**Fajlovi:** `Views/Tasks/TaskFormView.swift`, `ViewModels/TaskFormViewModel.swift`, izmene u `StudyTaskService` (`insert`, `update`, `delete`), `TasksView`, `TasksViewModel`.

**Zahtevi:**
- Forma: `TextField` naslov, `Picker` predmet, `Toggle` „Ima rok” koji prikazuje/sakriva `DatePicker`, `Stepper` procenjeno vreme (15–240, korak 15).
- Isti obrazac kao forma predmeta: dva režima, validacija naslova, prikaz greške.
- Forma prima opcioni unapred izabran predmet (koristi se u Slice 10).
- Prevlačenje ulevo: „Izmeni” i „Obriši” (bez potvrde).
- Ako nema nijednog predmeta, dugme „+” je onemogućeno uz poruku „Prvo dodaj predmet”.

**Provera:** dodaj zadatak sa rokom i bez roka; izmeni mu predmet i vreme; obriši ga. Sve promene su vidljive u bazi.

**Koncepti:** `Picker` sa objektima (`tag`), `Date?` i `Toggle` zajedno, `Stepper` sa korakom.

**Vežba:** promeni korak vremena na 10 minuta i maksimum na 180. Dodaj potvrdu pre brisanja zadatka.

---

### Slice 10 — Zadaci u detalju predmeta

**Cilj:** Detalj predmeta prikazuje zadatke tog predmeta i omogućava rad sa njima.

**Fajlovi:** izmene u `StudyTaskService` (`fetch(forCourse:)`), `CourseDetailViewModel`, `CourseDetailView`.

**Zahtevi:**
- Sekcija „Zadaci” prikazuje samo zadatke tog predmeta (filtrirano upitom po `course_id`, ne u Swift-u), koristeći postojeći `TaskRow`.
- Štikliranje radi kao u tabu Zadaci.
- Dugme „Dodaj zadatak” otvara `TaskFormView` sa unapred izabranim predmetom.
- Prazno stanje: „Nema zadataka za ovaj predmet”.

**Provera:** svaki predmet prikazuje samo svoje zadatke; novi zadatak dodat odavde vidi se i u tabu Zadaci.

**Koncepti:** filtriranje na serveru (`.eq`), ponovna upotreba komponenti, prosleđivanje podataka između View-ova.

**Vežba:** prikaži ispod naslova sekcije ukupno preostalo vreme, npr. „Preostalo: 2 h 30 min”.

---

### Slice 11 — Procena spremnosti

**Cilj:** aplikacija računa i prikazuje spremnost za svaki predmet.

**Fajlovi:** `Logic/ReadinessCalculator.swift`, `CampusMateTests/ReadinessCalculatorTests.swift`, `Views/Components/ReadinessView.swift`, izmene u `CourseDetailViewModel`, `CourseDetailView`.

**Zahtevi:**
- `score` i `pace` tačno po sekciji 5.2. Prvo logika i testovi, pa tek onda prikaz.
- Testovi pokrivaju: bez zadataka, svi završeni, pola vremena završeno (ne pola broja zadataka), svaku vrednost `Pace`, ispit danas (deljenje sa `max(…, 1)`).
- `ReadinessView`: procenat, `ProgressView(value:)` i oznaka tempa u odgovarajućoj boji.
- Detalj predmeta prikazuje `ReadinessView` umesto teksta „Uskoro”; vrednost se menja odmah nakon štikliranja zadatka.

**Provera:** testovi prolaze. Za jedan predmet ručno izračunaj procenat iz test podataka i uporedi sa ekranom. Štikliraj zadatak → procenat raste.

**Koncepti:** čiste funkcije, `reduce`, `enum` sa izračunatim svojstvima, celobrojno i decimalno deljenje, XCTest (`XCTAssertEqual`).

**Vežba:** promeni pragove tempa na 45 i 90 minuta i popravi testove koji zbog toga padnu.

---

### Slice 12 — `DailyPlanner` logika

**Cilj:** čista logika koja bira zadatke za danas; bez ikakvog interfejsa.

**Fajlovi:** `Logic/DailyPlanner.swift`, `CampusMateTests/DailyPlannerTests.swift`.

**Zahtevi:**
- Implementacija tačno po sekciji 5.3, sa odvojenim funkcijama `priority(...)` i `plan(...)`.
- Testovi: završeni zadaci se ne biraju; predmet sa prošlim ispitom se preskače; zadatak sa prošlim rokom je prvi; teži predmet sa istim rokom ima prednost; budžet se ne prekoračuje; preveliki zadatak se preskače a manji posle njega ulazi; pravilo iz tačke 6.

**Van opsega:** ekran, ViewModel, mreža.

**Provera:** svi testovi prolaze. Student ručno izračuna prioritet za dva zadatka iz test podataka i uporedi sa rezultatom testa.

**Koncepti:** `sorted(by:)`, `compactMap`, `Dictionary` za pronalaženje predmeta po `id`, pohlepni algoritam, testiranje sa fiksnim `now`.

**Vežba:** promeni formulu tako da zadaci kraći od 20 minuta dobiju +5 na prioritet i dodaj test za to. Zatim vrati na staro.

---

### Slice 13 — Ekran Dnevni plan

**Cilj:** tab Danas prikazuje predložene zadatke za današnji dan.

**Fajlovi:** `ViewModels/DailyPlanViewModel.swift`, `Views/DailyPlan/DailyPlanView.swift`.

**Zahtevi:**
- ViewModel učitava predmete i zadatke i poziva `DailyPlanner.plan`.
- Dnevni budžet se čuva u `@AppStorage("dailyBudgetMinutes")`, podrazumevano 120; menja se `Stepper`-om na vrhu (30–480, korak 30). Promena odmah preračunava plan bez novog učitavanja iz baze.
- Lista predloženih zadataka koristi `TaskRow`; ispod liste zbir: „Planirano: 105 od 120 min”.
- Štikliranje zadatka ga uklanja iz plana i plan se preračunava.
- Prazno stanje: „Nema zadataka za danas 🎉”.

**Provera:** zadatak sa prošlim rokom je prvi; smanji budžet na 30 → lista se skraćuje; ugasi i ponovo pokreni aplikaciju → budžet je zapamćen.

**Koncepti:** `@AppStorage` / `UserDefaults`, `onChange`, razlika između učitavanja podataka i preračunavanja.

**Vežba:** promeni podrazumevani budžet na 90. Pored svakog zadatka prikaži njegov prioritet zaokružen na jednu decimalu.

---

### Slice 14 — Dashboard

**Cilj:** tab Početna daje pregled stanja na jednom ekranu.

**Fajlovi:** `ViewModels/DashboardViewModel.swift`, `Views/Dashboard/DashboardView.swift`, `Views/Components/StatCard.swift`.

**Zahtevi:**
- Kartica „Najbliži ispit”: prvi predmet čiji ispit nije prošao — naziv, odbrojavanje, `ReadinessView`. Ako ga nema: „Nema zakazanih ispita”.
- Kartica „Za danas”: prva 3 zadatka iz `DailyPlanner.plan` (isti budžet iz `@AppStorage`) i ukupan broj planiranih.
- Dve male `StatCard` kartice: „Predmeta” (ukupan broj) i „Prosečna spremnost” (prosek `score` za predmete čiji ispit nije prošao; 0 ako ih nema).
- Sva računanja su u ViewModel-u ili u `Logic/`, View samo prikazuje.

**Van opsega:** navigacija sa kartica na druge tabove.

**Provera:** vrednosti se slažu sa tabovima Predmeti, Danas i sa Detaljem predmeta. Štikliraj zadatak u tabu Zadaci, vrati se na Početnu → vrednosti su ažurirane.

**Koncepti:** `ScrollView` + `VStack`/`Grid`, izdvajanje komponenti, `first(where:)`, `prefix`, prosek preko `reduce`.

**Vežba:** dodaj treću `StatCard` karticu „Završeno zadataka” u formatu „3/8”.

---

### Slice 15 — AI planiranje: ekran + lokalni generator

**Cilj:** ekran za plan učenja radi u potpunosti **bez AI servisa**.

**Fajlovi:** `Services/PlanGenerating.swift` (protokol + `PlanRequest`), `Logic/LocalPlanGenerator.swift`, `CampusMateTests/LocalPlanGeneratorTests.swift`, `ViewModels/AIPlannerViewModel.swift`, `Views/AIPlanner/AIPlannerView.swift`.

**Zahtevi:**
- `protocol PlanGenerating { func generatePlan(for request: PlanRequest) async throws -> String }`
- `LocalPlanGenerator` implementira protokol po sekciji 5.4; testovi za: zadaci staju u vreme, ostatak ≥ 15 min, bez zadataka, ispit za ≤ 2 dana.
- Forma: `Picker` predmet, `DatePicker` datum ispita (popunjava se iz izabranog predmeta; izmena ovde **ne menja** predmet u bazi), `Stepper` dostupno vreme (15–480, korak 15), dugme „Generiši plan”.
- Rezultat se prikazuje ispod forme u posebnoj sekciji, sa oznakom izvora „Lokalni plan”.
- ViewModel sam sastavlja `PlanRequest` (otvoreni zadaci izabranog predmeta).

**Van opsega:** mrežni poziv ka AI, čuvanje plana u bazu.

**Provera:** izaberi „Baze podataka”, 90 minuta → dobijaš numerisan plan od stvarnih zadataka tog predmeta. Testovi prolaze.

**Koncepti:** `protocol` i zašto ga ovde uvodimo (dve implementacije iste sposobnosti), sastavljanje teksta (`joined`, interpolacija), `Encodable`.

**Vežba:** promeni format lokalnog plana tako da svaka stavka počinje sa „•” umesto rednog broja i popravi testove.

---

### Slice 16 — Edge Function + AI generator + fallback

**Cilj:** plan generiše AI; ako AI nije dostupan, aplikacija sama pređe na lokalni plan.

**Ručno (student, pre agenta):** izaberi AI provajdera, napravi API ključ i upiši ga u Supabase → Edge Functions → Secrets kao `AI_API_KEY`. Ključ ne šalji agentu.

**Fajlovi:** `supabase/functions/generate-study-plan/index.ts`, `Services/AIPlanGenerator.swift`, izmene u `AIPlannerViewModel`, `AIPlannerView`.

**Zahtevi:**
- Edge Function `generate-study-plan`: prima JSON `PlanRequest`, čita `AI_API_KEY` iz okruženja, šalje jedan zahtev izabranom provajderu i vraća `{ "plan": "<tekst>" }`. Agent pre pisanja proveri aktuelnu dokumentaciju provajdera (endpoint, naziv modela) i aktuelna Supabase uputstva za pozivanje funkcije javnim ključem.
- Uputstvo modelu: odgovori na srpskom, najviše 6 kratkih stavki, konkretne aktivnosti sa minutima, bez uvoda i zaključka, zbir minuta ne prelazi dostupno vreme.
- Za loš ulaz funkcija vraća status 400, za grešku provajdera 502.
- `AIPlanGenerator` implementira `PlanGenerating` i poziva funkciju preko Supabase klijenta.
- ViewModel: prvo `AIPlanGenerator`; ako baci grešku ili ne odgovori za 15 sekundi → `LocalPlanGenerator`. Uz rezultat pamti izvor (`.ai` / `.local`).
- Ekran: tokom čekanja `ProgressView` i onemogućeno dugme; oznaka „AI plan” ili „Lokalni plan (AI nije dostupan)”.

**Provera:**
- Agent testira funkciju direktno (pre Swift koda) i pokaže odgovor.
- U aplikaciji: plan stiže sa oznakom „AI plan”.
- Uključi Airplane Mode u simulatoru/telefonu ili privremeno promeni naziv funkcije u kodu → dobijaš lokalni plan sa odgovarajućom oznakom, bez rušenja.

**Koncepti:** zašto API ključ ne sme u aplikaciju, serverless funkcija, polimorfizam preko protokola, obrada grešaka i fallback, vremensko ograničenje za `async` poziv.

**Vežba:** izmeni uputstvo modelu tako da na kraju plana uvek doda jednu rečenicu motivacije. Objasni gde bi dodao trećeg generatora (npr. drugi AI provajder) i šta bi u ViewModel-u moralo da se promeni.

---

### Slice 17 — Čuvanje planova i istorija

**Cilj:** generisani plan može da se sačuva i kasnije ponovo pogleda.

**Fajlovi:** `Models/StudyPlan.swift`, `Services/StudyPlanService.swift` (`insert`, `fetchRecent`, `delete`), izmene u `AIPlannerViewModel`, `AIPlannerView`, novi `Views/AIPlanner/PlanHistoryView.swift`.

**Zahtevi:**
- Dugme „Sačuvaj plan” ispod rezultata upisuje red u `study_plans` (predmet, minuti, tekst, izvor). Posle čuvanja dugme prelazi u „Sačuvano ✓”.
- Dugme u toolbar-u otvara „Istorija planova”: poslednjih 20 planova, najnoviji prvi — naziv predmeta, datum, izvor; dodir prikazuje ceo tekst; prevlačenje briše.

**Provera:** sačuvaj jedan AI i jedan lokalni plan → oba su u istoriji i u tabeli `study_plans` sa ispravnim `source`. Obriši predmet → njegovi planovi nestaju iz istorije.

**Koncepti:** `limit` i `order` u upitu, formatiranje datuma, `enum` u bazi kao tekst.

**Vežba:** ograniči istoriju na 5 planova. Dodaj filter da se prikazuju samo AI planovi.

---

### Slice 18 — Doterivanje i priprema za odbranu

**Cilj:** aplikacija je ujednačena, a student je bar jednom sam prošao kroz promenu „od baze do ekrana”.

**Zahtevi (agent):**
- Prođi sve ekrane: svaki ima stanje učitavanja, greške i prazno stanje; poruke su na srpskom i ujednačene.
- Proveri da se podaci osvežavaju pri povratku na tab posle izmene u drugom tabu; ako negde ne, popravi na najjednostavniji način i objasni.
- Ukloni mrtav kod, privremene `print` pozive i neiskorišćene fajlove.
- Napiši `README.md`: opis, snimci ekrana (mesta za njih), arhitektura u 10 rečenica, kako se pokreće (uključujući `Secrets.swift`).

**Provera:** pređi ceo tok bez rušenja: dodaj predmet → dodaj 3 zadatka → štikliraj jedan → pogledaj spremnost → Danas → Početna → generiši i sačuvaj plan → obriši predmet. Svi testovi prolaze.

**Vežba (završna, bez agenta):** dodaj predmetu polje **ESPB** (ceo broj 1–30). Koraci koje treba sam da pronađeš i uradiš:
1. migracija: nova kolona sa `default` i `check`,
2. `Course` + `CodingKeys`,
3. `CourseFormViewModel` i `CourseFormView` (`Stepper`),
4. prikaz u `CourseRow` ili `CourseDetailView`.

---

## 8. Šta profesor najverovatnije traži i gde se to menja

| Zahtev | Gde |
|---|---|
| „Dodaj novo polje u predmet/zadatak” | migracija → `Models/` (+ `CodingKeys`) → `…FormViewModel` → `…FormView` → red ili detalj |
| „Promeni kako se računa spremnost / prioritet” | `Logic/ReadinessCalculator.swift` ili `Logic/DailyPlanner.swift` + testovi |
| „Sortiraj / filtriraj listu drugačije” | upit u `Services/` ili izračunato svojstvo u ViewModel-u |
| „Dodaj validaciju u formu” | `…FormViewModel` (pravilo) + `…FormView` (poruka, onemogućeno dugme) |
| „Promeni izgled reda / kartice” | `CourseRow`, `TaskRow`, `StatCard`, `ReadinessView` |
| „Dodaj novi tab ili ekran” | `App/RootTabView.swift` + novi View i ViewModel |
| „Promeni tekst koji AI dobija” | `supabase/functions/generate-study-plan/index.ts` |
| „Šta se desi kad nema interneta?” | `do/catch` u ViewModel-ima; fallback u `AIPlannerViewModel` |
| „Objasni tok podataka od dodira do baze” | View → ViewModel funkcija → Service → Supabase → nazad u svojstvo ViewModel-a → View se sam ponovo iscrta |
