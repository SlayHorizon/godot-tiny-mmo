# Audyt docs — plik po pliku (`main` i `shop`)

**Data:** 2026-10-14. **Status:** audyt oryginalnych ścieżek, **częściowo wykonany** na gałęzi porządkującej. Przeniesiono 39 dokumentów i usunięto 19 historycznych plików; `shop` pozostał nietknięty. Historyczne nazwy w tabeli nie oznaczają aktualnych lokalizacji. Sprawdzono zawartość/nagłówki i aktualność dokumentów tekstowych; dwa PDF-y oceniono na podstawie ich towarzyszących Markdown (zgodność PDF nie została porównana). Surowe pliki danych klasyfikowano według użycia i pochodzenia. Zanim usuniemy pliki, trzeba jeszcze sprawdzić wszystkie linki i odwołania z kodu.

**Łącznie:** 66 istniejących plików `docs/` na `main` i 31 nowych na `shop` (razem 97). **Rekomendacje po przeglądzie:** ZOSTAW: 29, SCAL → USUŃ: 39, USUŃ: 26, DOWÓD: 3. Indeksy dodane w osobnym PR #5 są narzędziem nawigacyjnym, a nie częścią tej bazowej liczby.

**Jak czytać:** *ZOSTAW* = aktywny kontrakt/decyzja/test; *SCAL → USUŃ* = przenieść istotną treść do kanonicznego przewodnika, następnie skasować oryginał; *USUŃ* = zakończone lub historyczne materiały, do skasowania po naprawieniu referencji; *DOWÓD* = raport danych, którego nie warto niszczyć tylko dla estetyki katalogu. Wszystko pozostaje w historii Gita.

## Main — 66 plików (oryginalne ścieżki przed cleanupem)

| Plik | Propozycja | Powód |
| --- | --- | --- |
| `docs/architecture/economy/C1-ownership.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/architecture/economy/C2-commands.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/architecture/economy/C3-transactions.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/architecture/economy/C4-synchronization.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/architecture/economy/C5-lifecycle.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/architecture/economy/README.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/camera-v1.md` | **SCAL → USUŃ** | Skrócić do bieżącego przewodnika obsługi kamery |
| `docs/cef-addon-integration.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/cef-ui-spike.md` | **USUŃ** | Wycofany testowy klient CEF, nieaktualna architektura |
| `docs/character-xp.md` | **SCAL → USUŃ** | Przenieść działające reguły XP i checkpointów do persistence |
| `docs/ci.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/cleanup-2-removed-assets.txt` | **USUŃ** | Manifest dawnego usuwania assetów; historia Git przechowuje różnicę |
| `docs/combat-feel.md` | **USUŃ** | Pierwsza wersja combatu; zastąpiona kontraktami Warrior |
| `docs/core-ui.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/first-region-graybox.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/history/inventory-validation-2026-10-09.md` | **USUŃ** | Zapis starego fixture, wycofanego z bieżącej walidacji |
| `docs/history/project-direction-2026-10-09.md` | **USUŃ** | Nieaktualna sekwencja decyzji, obecny kierunek w nowym ADR |
| `docs/history/README.md` | **SCAL → USUŃ** | Po usunięciu starych zapisów zostawić krótki odsyłacz do historii Git |
| `docs/history/web-ui-validation-2026-10-08.md` | **USUŃ** | Stara walidacja wycofanego klienta CEF |
| `docs/hit-reactions-v1.md` | **SCAL → USUŃ** | Scalić mechanikę reakcji z dokumentacją obecnego combatu |
| `docs/inherited-runtime.md` | **SCAL → USUŃ** | Zachować ryzyka kwarantanny starych modułów w krótkim dokumencie |
| `docs/inventory-ui-prototype.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/item-drag-runtime.md` | **SCAL → USUŃ** | Kontrakt drag można przenieść do Core UI |
| `docs/item-instances.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/item-progression.md` | **USUŃ** | Zakończony milestone z października, stare założenia |
| `docs/item-tooltips.md` | **SCAL → USUŃ** | Kontrakt tooltipa można przenieść do Core UI |
| `docs/legacy-asset-pipeline.md` | **USUŃ** | Wycofany konwerter; przed skasowaniem zachować atrybucję/licencje |
| `docs/legacy-ui-cache.md` | **SCAL → USUŃ** | Nisza lokalnego exportu UI; przenieść krótką instrukcję do local-dev-visuals |
| `docs/local-dev-visuals.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/Mandate_of_Three_Design_Decisions.md` | **SCAL → USUŃ** | Zawiera wyraźnie **zastąpione** założenie „bez ręcznych CH, tylko ukryte layery”. Zachować tylko nadal aktualne propozycje bossów, drużyn i progresji w nowym dokumencie gameplay; prymat ma ADR `world-instance-architecture.md` |
| `docs/Mandate_of_Three_Design_Decisions.pdf` | **SCAL → USUŃ** | PDF prawdopodobnie dubluje Markdown; porównać treść przed usunięciem |
| `docs/Mandate-of-Three_TinyMMO_Spike_Plan.md` | **USUŃ** | Zrealizowany pierwszy plan spike, zastąpiony aktualnymi kontraktami |
| `docs/Mandate-of-Three_TinyMMO_Spike_Plan.pdf` | **USUŃ** | Historyczna wersja oryginalnego spike-plan, do odzyskania z Git |
| `docs/metin-encounter-v1.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/mob-packs-v1.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/npc-services.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/npc-shop.md` | **SCAL → USUŃ** | Z działającego Shop zachować zakres autoryzacji i testy w NPC services |
| `docs/npc-upgrade-ui.md` | **SCAL → USUŃ** | Z działającego Upgrade zachować kontrakt i testy w NPC services |
| `docs/open-mt2-analysis.md` | **USUŃ** | Historyczna analiza obcego projektu, stare rekomendacje |
| `docs/persistence-policy.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/project-direction.md` | **ZOSTAW (przepisać)** | Kanoniczny kierunek projektu używany m.in. przez `AGENTS.md`; skrócić do żywych zasad i najbliższych priorytetów, wyprowadzić kronikę zakończonych etapów |
| `docs/pve-ground-loot.md` | **USUŃ** | Autor oznaczył pierwszą implementację PvE jako historyczną |
| `docs/repository-cleanup.md` | **USUŃ** | Kronika porządkowania starego forka, nie bieżąca polityka |
| `docs/spike-graduation-cleanup.md` | **USUŃ** | Wykonany i zmergowany cleanup pakietu spike |
| `docs/spike-graduation-plan.md` | **USUŃ** | Wykonany plan A/B/C, nieaktualna lista zadań |
| `docs/spike-package-b-plan.md` | **USUŃ** | Wykonany plan ekstrakcji Combat, nie bieżące zadania |
| `docs/spike-package-c-plan.md` | **USUŃ** | Wykonany plan ekstrakcji Core UI |
| `docs/spike3d.md` | **USUŃ** | Historyczny prototyp mapy, zastąpiony First Region |
| `docs/testing.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/third-party-credits.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/TODO.md` | **SCAL → USUŃ** | Nowy plan w `docs/plans/architecture-hardening.md` i indeks `docs/plans/README.md` zastępują osobny TODO. Zlikwidować drugi backlog, po przeniesieniu ewentualnych żywych zadań |
| `docs/ui-contract.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/visual-upgrade-v0.md` | **SCAL → USUŃ** | Kluczowe CEF/Vulkan gates przenieść do instrukcji renderingu |
| `docs/visual-upgrade-v1.md` | **SCAL → USUŃ** | Włączyć ustawienia Sky3D do zbiorczej instrukcji visuals |
| `docs/visual-upgrade-v2.md` | **SCAL → USUŃ** | Włączyć reguły zegara, nieba i dnia/nocy do visuals |
| `docs/visual-upgrade-v3.md` | **SCAL → USUŃ** | Włączyć reguły wody i shadera do visuals |
| `docs/visual-upgrade-v4-terrain3d.md` | **ZOSTAW (zaktualizować)** | Unikalne dowody zgodności Terrain3D, nie zapisywać ich od nowa z pamięci; usunąć historyczne stwierdzenia o statusie brancha i „nie zmergowano” z aktualnej części |
| `docs/warrior-action-polish.md` | **SCAL → USUŃ** | Połączyć stan maszynowy akcji/impact z dokumentem Warrior |
| `docs/warrior-basic-combo-v2.md` | **SCAL → USUŃ** | Połączyć aktualny timing kombosów w dokumencie Warrior |
| `docs/warrior-body-collision.md` | **SCAL → USUŃ** | Połączyć mechanikę BODY i ruchu w dokumencie Warrior |
| `docs/warrior-combat-feel-v2.md` | **SCAL → USUŃ** | Połączyć Attack Speed, buffer i prezentację w doc Warrior |
| `docs/warrior-combat-trace-v1.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/warrior-compatibility.md` | **SCAL → USUŃ** | Włączyć lokalny workflow assetów do local-dev-visuals |
| `docs/web-ui.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/world-instance-architecture.md` | **ZOSTAW** | Aktywny kontrakt, instrukcja lub materialne decyzje — zachować po aktualizacji linków |
| `docs/yang-wallet.md` | **SCAL → USUŃ** | Stary wallet testowy; reguły aktualne w persistence, docelowe w C3 |

## Shop — 31 dodatkowych plików (jeszcze nieporządkowane)

**Uwaga:** `shop` jeszcze nie zawiera C1–C5 z nowego `main`. Po integracji należy powtórzyć sprawdzenie linków i nie uznawać starszego Marketplace E0–E5 za bieżącą specyfikację C3.

| Plik | Propozycja po merge | Powód |
| --- | --- | --- |
| `docs/evidence/auction-d1a/results.json` | **DOWÓD** | Dowód migracji indeksu, przechować do konsolidacji |
| `docs/evidence/auction-d2/windows/results.json` | **DOWÓD** | Aktualne porównanie wydajności pod obciążeniem |
| `docs/evidence/auction-d2/windows/validation.json` | **DOWÓD** | Aktualne potwierdzenie scenariuszy D2 |
| `docs/evidence/auction-soci-p0/baseline-broad-pure.txt` | **USUŃ** | Historyczne SQL do P0, wynik w raporcie i Git |
| `docs/evidence/auction-soci-p0/distributions.csv` | **USUŃ** | Surowe rozkłady debugowania P0 |
| `docs/evidence/auction-soci-p0/lookup-broad-pure.txt` | **USUŃ** | Historyczne SQL po poprawie indeksu |
| `docs/evidence/auction-soci-p0/plans.json` | **SCAL → USUŃ** | Wyciągnąć kluczowe EXPLAIN/index wyniki do zbiorczego raportu |
| `docs/evidence/auction-soci-p0/provenance.json` | **SCAL → USUŃ** | Zachować wersje/hashe w raporcie, resztę danych zostawić w Git |
| `docs/evidence/auction-soci-p0/pure-353-o2-nodebug-baseline-broad.csv` | **USUŃ** | Przejściowy mikrobenchmark biblioteki |
| `docs/evidence/auction-soci-p0/pure-353-o2-nodebug-lookup-broad.csv` | **USUŃ** | Przejściowy mikrobenchmark biblioteki |
| `docs/evidence/auction-soci-p0/quick-summary.json` | **SCAL → USUŃ** | Przepisać istotne wnioski do jednej historii Auction |
| `docs/evidence/auction-soci-p0/README.md` | **SCAL → USUŃ** | Po wyjęciu próbek archiwalnych usunąć osobny indeks P0 |
| `docs/evidence/auction-soci-p0/samples.csv` | **USUŃ** | Duży zbiór surowych pomiarów, do odzyskania z historii Git |
| `docs/evidence/auction-soci-p0/wait-mode-comparison.json` | **USUŃ** | Dawny eksperyment wait mode |
| `docs/marketplace-auction-d1a.md` | **SCAL → USUŃ** | Zachować migrację indeksu i testy w jednym Auction doc |
| `docs/marketplace-auction-d1b.md` | **ZOSTAW** | Aktualny kontrakt lub test implementacyjny Marketplace/Auction — nie kasować przed integracją |
| `docs/marketplace-auction-d2.md` | **ZOSTAW** | Aktualny kontrakt lub test implementacyjny Marketplace/Auction — nie kasować przed integracją |
| `docs/marketplace-auction-dispatcher.md` | **SCAL → USUŃ** | Wycofane D0/S0 proof, wiele zdań o nieistniejącym D1; wyciągnąć unikalne wnioski |
| `docs/marketplace-auction-soci-p0.md` | **SCAL → USUŃ** | Historyczny wybór SOCI; skrócić do decyzji o wydaniu/indexie |
| `docs/marketplace-e0a-identity.md` | **SCAL → USUŃ** | Wyciągnąć granice tożsamości i migrację schematu |
| `docs/marketplace-e0b-wallet.md` | **SCAL → USUŃ** | Wyciągnąć rachunek konta i migrację schematu |
| `docs/marketplace-e1a-custody.md` | **ZOSTAW** | Aktualny kontrakt lub test implementacyjny Marketplace/Auction — nie kasować przed integracją |
| `docs/marketplace-e1b-my-shop.md` | **SCAL → USUŃ** | Dawne założenia Shop są zastępowane przez C3, zachować stan wdrożenia |
| `docs/marketplace-e2-purchase.md` | **SCAL → USUŃ** | Zachować transakcyjne testy zakupu i przenieść do Marketplace |
| `docs/marketplace-e3a-search.md` | **SCAL → USUŃ** | Zachować filtry/indexy w Auction |
| `docs/marketplace-e3b-browser.md` | **SCAL → USUŃ** | Zachować granice Trading Glass w Marketplace |
| `docs/marketplace-e4-ledger.md` | **SCAL → USUŃ** | Zachować rezerwacje w Exchange |
| `docs/marketplace-e5-exchange.md` | **ZOSTAW** | Aktualny kontrakt lub test implementacyjny Marketplace/Auction — nie kasować przed integracją |
| `docs/marketplace-implementation-plan.md` | **USUŃ** | Ukończony E0–E5; reguły produktu częściowo sprzeczne z C3 |
| `docs/marketplace-refactor-r0-r2.md` | **SCAL → USUŃ** | Wyniki pomiarów i admission przenieść do Auction |
| `docs/marketplace-refactor-r3-r4.md` | **SCAL → USUŃ** | Zachować obecny podział Store/Service w dokumencie architektury |

## Wnioski po weryfikacji treści i zależności

- **Nie jest to lista do automatycznego `git rm`.** Przeczytano nagłówki i fragmenty treści oryginalnych Markdown z `main` oraz dodatkowych raportów `shop`; sprawdzono też kluczowe kontrakty (Economy C1–C5, Shop/E0–E5, Terrain3D, aktualne UI, Warrior) oraz dokumenty, które są źródłami linków. Audyt nadal **nie zastępuje** pełnego skanu odnośników z kodu i testów. PDF-y nie były porównywane binarnie.
- **Najważniejsza realna sprzeczność:** `Mandate_of_Three_Design_Decisions.md` mówi „avoid manually selectable CH”; zaakceptowany `world-instance-architecture.md` wybiera dynamiczne, widoczne CH jako preferowaną politykę. Nie używać starszego dokumentu jako instrukcji dla Codexa. Pozostałe pomysły gameplayowe odzyskać selektywnie, zamiast zachować dwie „aktualne” specyfikacje.
- **Nie usuwać `project-direction.md`:** `AGENTS.md` wskazuje go jako źródło bieżących priorytetów. Utrzymać mały, aktualny dokument; nie dopisywać historii kolejnych milestone’ów.
- **Dokumenty wyglądające na sprawozdania, ale zawierające wykonywalne kontrakty:** `warrior-combat-trace-v1.md` (konkretne ms okien ciosów i geometria), `visual-upgrade-v4-terrain3d.md` (dowód złej serializacji i persystencji Terrain3D), `core-ui.md`, `web-ui.md`, `inventory-ui-prototype.md`, `item-instances.md`, `persistence-policy.md` i `testing.md`. Zachować do czasu świadomego skrócenia; nie klasyfikować po słowach `spike`/`prototype` w nazwie.
- **Licencje i przypisanie źródeł:** `third-party-credits.md` pozostaje. Przed usunięciem `legacy-asset-pipeline.md` sprawdzić, czy istotne ostrzeżenia licencyjne i workflow lokalnych assetów są w `local-dev-visuals.md`.
- **Linki do usuwanych plików występują już teraz:** główny `README.md` linkuje do spike, starego PvE, Combat Feel, Open-MT2, PDF-ów itd.; `docs/project-direction.md`, `docs/plans/README.md`, `docs/implemented/README.md` i `docs/history/README.md` również wymagają poprawy. Bez aktualizacji linków mechaniczne kasowanie będzie regresją.
- **Szacunek po konsolidacji:** około 29 oryginalnych dokumentów pozostanie samodzielnych, a około 65 plików tekstowych/historycznych można docelowo skasować z aktualnego drzewa (z tego 39 dopiero po przeniesieniu aktualnych fragmentów). Surowe dowody D2 zostają; duże diagnostyczne P0 dopiero po sprawdzeniu, czy dane nie są potrzebne do powtórzenia porównań.
- **`shop` i `main` mają inne zestawy dokumentów:** Marketplace/Auction E0–E5 i D0–D2 nie wolno usuwać z bieżącej gałęzi `shop` przed zakończeniem integracji PR #1. W następnym etapie usunąć stary `marketplace-implementation-plan.md` i skonsolidować raporty, ale zachować granice UID custody, Exchange, D1b oraz D2 i powtarzalne testy.

## Sposób czyszczenia

1. Zatwierdzić listę usuwania. Dokumentów „SCAL” **nie kasować**, dopóki nie przeniesiemy ich aktualnych reguł (Warrior, V1–V3 visuals, NPC, Marketplace) do zwięzłych dokumentów kanonicznych.
2. Poprawić linki z całego `README.md`, `docs/`, `AGENTS.md`, testów, skryptów i komentarzy w kodzie. Przy każdym usunięciu przejrzeć plik diff; nie ufać automatycznemu usuwaniu opartego wyłącznie na nazwie.
3. Przed kasacją oryginalnych PDF-ów potwierdzić ich zawartość względem wersji Markdown.
4. Materiały `shop` usuwać/scalić **po** prawidłowym merge PR #1 i ponownym przetestowaniu. Obecny PR #5 nie powinien zmieniać kodu ani zasad transakcji podczas tego review.
5. Zostawić informacje licencyjne, bieżące instrukcje CEF, testing, persistence, C1–C5/World ADR i istotne dowody Auction D2. Nie robić z katalogu `docs/` repozytorium historii każdego zamkniętego PR.

## Decyzje otwarte

- Czy usuwamy oba stare PDF-y, jeśli markdown/commit history zachowają treść?
- Czy surowy P0 SOCI (kilkaset KB JSON + ponad 1 MB CSV) może zostać tylko w historii Git, skoro nowsze D1/D2 dają bieżący punkt odniesienia?
- Po merge `shop`: rekomenduję zostawić osobne szczegółowe `E1a custody`, `E5 Exchange`, `Auction D1b` i `Auction D2`, a resztę scalić. Pozwala to ograniczyć liczbę plików bez zgubienia trudnych reguł rollback/recovery.
