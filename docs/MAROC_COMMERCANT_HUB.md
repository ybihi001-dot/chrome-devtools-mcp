# MarocCommercantHub

> Plateforme e-commerce B2C pour commercants marocains — GitHub + Supabase + Vercel

## Structure du projet

```
maroc-commercant-hub/
|-- sql/
|   |-- maroc_commercant_hub_schema.sql   # Schema Supabase complet
|-- scripts/
|   |-- setup.sh                          # Script setup automatique
|-- docs/
    |-- MAROC_COMMERCANT_HUB.md           # Ce fichier
```

## Schema de base de donnees (Supabase)

### Tables principales

| Table | Description |
|-------|-------------|
| `merchants` | Commercants inscrits (profil, localisation, statut) |
| `products` | Produits avec prix, stock, categorie |
| `orders` | Commandes clients |
| `order_items` | Lignes de commandes |
| `reviews` | Avis et notes (1-5 etoiles) |
| `messages` | Chat entre marchands et clients |
| `notifications` | Alertes en temps reel |
| `coupons` | Codes promo (% ou montant fixe) |
| `favorites` | Produits favoris des clients |
| `merchant_analytics` | Stats journalieres par marchand |

### Securite (RLS)

- **Marchands** : acces en lecture/ecriture uniquement a leurs propres donnees
- **Clients** : acces a leurs commandes et favoris
- **Admin** : acces total
- **Public** : lecture des produits actifs et profils marchands

### Fonctions Supabase

- `get_merchant_stats(merchant_id)` : Statistiques completes d'un marchand
- `get_top_products(limit)` : Top produits par ventes
- `update_merchant_rating(merchant_id)` : Recalcule la note d'un marchand
- `handle_updated_at()` : Trigger pour mise a jour automatique de `updated_at`

## Deploiement rapide

### Prerequis

- Node.js >= 18
- Git
- Compte Supabase (https://supabase.com)
- Compte Vercel (https://vercel.com)

### Setup en une commande

```bash
chmod +x scripts/setup.sh && ./scripts/setup.sh
```

Le script effectue automatiquement :
1. Verification des dependances (git, node, npm, vercel CLI)
2. Configuration du depot GitHub
3. `npm install` et build
4. Verification du schema SQL
5. Commit et push automatique
6. Deploiement sur Vercel (optionnel)

### Configuration Supabase

1. Creez un nouveau projet sur [supabase.com](https://supabase.com)
2. Dans l'editeur SQL, importez `sql/maroc_commercant_hub_schema.sql`
3. Copiez `SUPABASE_URL` et `SUPABASE_ANON_KEY` depuis Parametres > API

### Variables d'environnement Vercel

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

## Donnees de test

Le schema inclut des donnees de test :
- 3 marchands marocains (Casablanca, Marrakech, Fes)
- Produits typiques marocains (djellabas, tajines, argan...)
- Exemples de commandes et avis

## Licence

MIT License - (c) 2026 MarocCommercantHub
