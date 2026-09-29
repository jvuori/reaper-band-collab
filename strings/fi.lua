-- Suomenkielinen käyttöliittymäteksti. Avaimet ovat samat kuin tiedostossa strings/en.lua.
-- err.<koodi>.what kertoo mitä tapahtui, err.<koodi>.action ehdottaa yhden seuraavan askeleen.
return {
  err = {
    missing_marker = { what = "Tämä paketti ei ole vielä valmis.", action = "Odota hetki, että tiedostot ehtivät perille, ja yritä uudelleen." },
    bad_manifest = { what = "Paketin tiedostoluettelo on vioittunut.", action = "Pyydä lähettämään paketti uudelleen." },
    marker_mismatch = { what = "Pakettia on muutettu sen valmistumisen jälkeen.", action = "Pyydä lähettämään paketti uudelleen." },
    missing_file = { what = "Tiedosto {path} puuttuu.", action = "Odota, että tiedostot ehtivät perille, tai pyydä lähettämään paketti uudelleen." },
    size_mismatch = { what = "Tiedosto {path} on keskeneräinen.", action = "Odota, että tiedosto ehtii perille, ja yritä uudelleen." },
    hash_mismatch = { what = "Tiedosto {path} on vioittunut.", action = "Pyydä lähettämään paketti uudelleen." },
    unreadable_file = { what = "Tiedostoa {path} ei voitu lukea.", action = "Tarkista, että tiedosto on tallessa tässä tietokoneessa, ja yritä uudelleen." },
    band_unreadable = { what = "Bändin asetuksia ei löytynyt.", action = "Tarkista, että valitsit oikean bändikansion." },
    band_invalid = { what = "Bändin asetustiedostossa on virhe ({detail}).", action = "Pyydä tuottajaa korjaamaan bändin asetukset." },
    band_too_new = { what = "Bändin asetukset on tehty tämän työkalun uudemmalla versiolla.", action = "Päivitä työkalu ja yritä uudelleen." },
  },
}
