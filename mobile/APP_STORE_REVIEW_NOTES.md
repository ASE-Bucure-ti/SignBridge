# App Store Review Notes — SignBridge Mobile

Paste into App Store Connect → Version 1.0 → App Review Information → Notes.

Prefer the language that matches your primary localization (Romanian). You can paste either block, or both.

---

## Romanian (copy below)

```
Ce face aplicația
SignBridge Mobile permite semnarea electronică a documentelor cu cartea electronică de identitate (CEI) din România, prin NFC (Core NFC Tag Reader + PACE). Semnătura se creează pe card; aplicația nu extrage și nu stochează cheia privată.

Hardware necesar
• iPhone cu NFC
• CEI românească activată pentru semnare
• CAN: 6 cifre tipărite pe fața cardului (dreapta-jos, sub data de expirare)
• PIN pentru semnare: 6 cifre ales la activarea CEI (nu CAN-ul, nu PIN-ul de autentificare din 4 cifre)

Notă pentru App Review: nu aveți CEI. Vă rugăm să urmăriți videoclipul demo atașat / linkuit pentru fluxul complet de semnare. Putem oferi și un walkthrough live dacă ne contactați.

Cum testați sample-ul din aplicație (cu CEI reală)
1. Completați onboarding-ul și salvați CAN-ul când sunteți solicitați.
2. Pe ecranul principal, țineți apăsat (long-press) pe logo-ul cu scut / utilizator verificat pentru a deschide semnarea PDF-ului de probă local.
3. Apropiați CEI-ul de iPhone când apare foaia NFC.
4. Introduceți PIN-ul pentru semnare când sunteți solicitați.
5. Așteptați finalizarea semnării.

Deep link (site-uri de producție)
Site-urile deschid SignBridge prin schema URL signbridge://… . Fără o cerere de pe site, ecranul principal așteaptă un deep link; long-press pe logo este demo-ul autonom.

Confidențialitate
• Politica de confidențialitate: https://ase-bucure-ti.github.io/SignBridge/privacy/
• CAN-ul este stocat pe dispozitiv în iOS Keychain.
• PIN-ul pentru semnare se introduce pe sesiune și nu este persistat.
• Fără publicitate / SDK-uri de tracking.

Contact
Folosiți câmpurile de contact App Review din App Store Connect. Răspundem rapid pe durata review-ului.
```

---

## English (copy below)

```
What the app does
SignBridge Mobile lets users digitally sign documents using a Romanian electronic identity card (CEI) over NFC (Core NFC Tag Reader + PACE). Signing happens on the card; the app does not extract or store the private key.

Hardware required
• iPhone with NFC
• Romanian CEI (activated for signing)
• CAN: 6 digits printed on the front of the card (bottom-right under expiry)
• Signing PIN: 6 digits chosen at CEI activation (not the CAN, not the 4-digit auth PIN)

Note for App Review: you do not have a CEI. Please watch the attached / linked demo video for a full signing flow. We can also provide a live walkthrough if contacted.

How to try the in-app sample (with a real CEI)
1. Complete onboarding and save the CAN when prompted.
2. On the home screen, long-press the shield / verified-user logo to open the local sample PDF signing flow.
3. Hold the CEI to the iPhone when the NFC sheet appears.
4. Enter the signing PIN when asked.
5. Wait until signing finishes.

Deep link (production websites)
Sites open SignBridge via the URL scheme signbridge://… . Without a site request, the idle home screen waits for a deep link; the long-press sample is the standalone demo.

Privacy
• Privacy policy: https://ase-bucure-ti.github.io/SignBridge/privacy/
• CAN is stored in the iOS Keychain on device.
• Signing PIN is entered per session and not persisted.
• No advertising / tracking SDKs.

Contact
Use the App Review contact fields in App Store Connect. We respond quickly during review.
```
