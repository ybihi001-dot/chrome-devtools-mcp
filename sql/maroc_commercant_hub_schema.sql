-- ============================================================
-- MarocCommercantHub — Supabase Schema (amélioré)
-- Version : 1.1 | Licence MIT
-- Contenu : RLS, triggers updated_at, tables supplémentaires,
-- contraintes, index, fonctions et données de test
-- ============================================================

-- -------------------------------------------------------
-- EXTENSION : UUID auto-generation
-- -------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -------------------------------------------------------
-- Helper : détection admin via JWT claims (Supabase)
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql AS $$
  SELECT (current_setting('jwt.claims.role', true) = 'admin') OR
         (current_setting('jwt.claims.is_admin', true) = 'true');
$$;

-- ============================================================
-- TABLE : merchants (multi-commerçants)
-- ============================================================
CREATE TABLE IF NOT EXISTS merchants (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,                 -- bcrypt en prod
  shop_name       TEXT NOT NULL,
  city            TEXT DEFAULT 'Casablanca',     -- Rabat | Casablanca | etc.
  phone           TEXT,                          -- WhatsApp contact
  plan            TEXT DEFAULT 'free',           -- free | pro
  locale          TEXT DEFAULT 'fr',             -- fr | ar | ma
  google_maps_url TEXT,                          -- SEO local
  rating_avg      NUMERIC(3,2),                  -- moyenne des avis
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchants_city ON merchants(city);

-- ============================================================
-- TABLE : products (catalogue + stock)
-- ============================================================
CREATE TABLE IF NOT EXISTS products (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  description   TEXT,
  category      TEXT DEFAULT 'mode',           -- mode | tech | deco | autre
  price_mad     NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (price_mad >= 0),
  stock         INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  stock_alert   INTEGER DEFAULT 3 CHECK (stock_alert >= 0),
  image_url     TEXT,                          -- URL photo produit
  jumia_link    TEXT,                          -- lien affilié Jumia
  is_flash_sale BOOLEAN DEFAULT FALSE,         -- vente flash activée
  flash_price   NUMERIC(10,2) CHECK (flash_price IS NULL OR flash_price >= 0),
  flash_ends_at TIMESTAMPTZ,                   -- fin de la vente flash
  sku           TEXT,                          -- référence interne
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_merchant_cat ON products(merchant_id, category);
CREATE INDEX IF NOT EXISTS idx_products_name_fts ON products USING gin (to_tsvector('simple', name));

-- ============================================================
-- TABLE : customers (CRM basique)
-- ============================================================
CREATE TABLE IF NOT EXISTS customers (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  full_name     TEXT NOT NULL,
  email         TEXT,
  phone         TEXT,                          -- numéro WhatsApp marocain
  city          TEXT,
  notes         TEXT,                          -- notes commerçant
  total_orders  INTEGER DEFAULT 0 CHECK (total_orders >= 0),
  total_spent   NUMERIC(12,2) DEFAULT 0 CHECK (total_spent >= 0),
  last_order_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_merchant_id ON customers(merchant_id);

-- ============================================================
-- TABLE : orders (commandes + panier)
-- ============================================================
CREATE TABLE IF NOT EXISTS orders (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id     UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  customer_id     UUID REFERENCES customers(id) ON DELETE SET NULL,
  items           JSONB NOT NULL DEFAULT '[]',
  -- Structure items : [{ product_id, name, price_mad, qty, image_url }]
  total_mad       NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_mad >= 0),
  status          TEXT DEFAULT 'pending',
  payment_method  TEXT DEFAULT 'cash',         -- cash | CMI | stripe | virement
  cmi_ref         TEXT,                        -- référence transaction CMI
  stripe_pi       TEXT,                        -- Stripe PaymentIntent ID
  invoice_url     TEXT,                        -- URL PDF facture Supabase Storage
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_merchant_status_created ON orders(merchant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id_created ON orders(customer_id, created_at DESC);

-- ============================================================
-- TABLE : order_items (détail lignes pour analytics précis)
-- ============================================================
CREATE TABLE IF NOT EXISTS order_items (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  UUID REFERENCES products(id) ON DELETE SET NULL,
  name        TEXT NOT NULL,
  price_mad   NUMERIC(12,2) NOT NULL CHECK (price_mad >= 0),
  qty         INTEGER NOT NULL DEFAULT 1 CHECK (qty > 0),
  subtotal    NUMERIC(14,2) GENERATED ALWAYS AS (price_mad * qty) STORED
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_product ON order_items(order_id, product_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

-- ============================================================
-- TABLE : reviews (avis produits)
-- ============================================================
CREATE TABLE IF NOT EXISTS reviews (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  buyer_id    UUID REFERENCES customers(id) ON DELETE SET NULL,
  rating      INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_product_rating ON reviews(product_id, rating DESC);

-- ============================================================
-- TABLE : messages (chat entre marchands et clients)
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  customer_id   UUID REFERENCES customers(id) ON DELETE CASCADE,
  sender        TEXT NOT NULL, -- 'merchant' | 'customer'
  body          TEXT NOT NULL,
  read_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(merchant_id, customer_id, created_at DESC);

-- ============================================================
-- TABLE : notifications
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID REFERENCES merchants(id) ON DELETE CASCADE,
  customer_id   UUID REFERENCES customers(id) ON DELETE CASCADE,
  type          TEXT NOT NULL, -- 'order' | 'message' | 'system'
  payload       JSONB,
  read          BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_merchant ON notifications(merchant_id, read, created_at DESC);

-- ============================================================
-- TABLE : coupons
-- ============================================================
CREATE TABLE IF NOT EXISTS coupons (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  code          TEXT NOT NULL,
  amount_off    NUMERIC(10,2) CHECK (amount_off IS NULL OR amount_off >= 0),
  percent_off   NUMERIC(5,2) CHECK (percent_off IS NULL OR (percent_off > 0 AND percent_off <= 100)),
  starts_at     TIMESTAMPTZ,
  ends_at       TIMESTAMPTZ,
  max_uses      INTEGER DEFAULT 0 CHECK (max_uses >= 0),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (merchant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_coupons_merchant_code ON coupons(merchant_id, code);

-- ============================================================
-- TABLE : favorites (produits favoris des clients)
-- ============================================================
CREATE TABLE IF NOT EXISTS favorites (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_unique ON favorites(merchant_id, customer_id, product_id);

-- ============================================================
-- TABLE : merchant_analytics (stats journalières)
-- ============================================================
CREATE TABLE IF NOT EXISTS merchant_analytics (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  date          DATE NOT NULL,
  visits        INTEGER DEFAULT 0 CHECK (visits >= 0),
  orders_count  INTEGER DEFAULT 0 CHECK (orders_count >= 0),
  revenue_mad   NUMERIC(12,2) DEFAULT 0 CHECK (revenue_mad >= 0),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (merchant_id, date)
);

CREATE INDEX IF NOT EXISTS idx_merchant_analytics_merchant_date ON merchant_analytics(merchant_id, date DESC);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================
-- Activer RLS sur toutes les tables gérées
ALTER TABLE merchants             ENABLE ROW LEVEL SECURITY;
ALTER TABLE products              ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers             ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders                ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items           ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews               ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages              ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications         ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupons               ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites             ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_analytics    ENABLE ROW LEVEL SECURITY;

-- Policies : merchants can see/modify uniquement leurs données; customers peuvent voir leurs commandes; admins ont tout accès

-- merchants table : le commerçant peut gérer sa propre row, admin peut tout
CREATE POLICY merchants_own_row ON merchants
  USING (id = auth.uid() OR is_admin())
  WITH CHECK (id = auth.uid() OR is_admin());

-- products : merchant owner or admin
CREATE POLICY products_owner ON products
  USING (merchant_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR is_admin());

-- customers : merchant owner or admin
CREATE POLICY customers_owner ON customers
  USING (merchant_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR is_admin());

-- orders : merchant owner OR customer who owns the order OR admin
CREATE POLICY orders_merchant_or_customer ON orders
  USING (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin());

-- order_items : accessible via order ownership
CREATE POLICY order_items_via_order ON order_items
  USING (EXISTS (SELECT 1 FROM orders o WHERE o.id = order_items.order_id AND (o.merchant_id = auth.uid() OR o.customer_id = auth.uid() OR is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM orders o WHERE o.id = order_items.order_id AND (o.merchant_id = auth.uid() OR o.customer_id = auth.uid() OR is_admin())));

-- reviews : public readable, but create only by customers and merchants for their products; admin peut gérer
CREATE POLICY reviews_read ON reviews
  FOR SELECT USING (TRUE);

CREATE POLICY reviews_manage ON reviews
  FOR ALL USING (buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM products p WHERE p.id = reviews.product_id AND p.merchant_id = auth.uid()) OR is_admin())
  WITH CHECK (buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM products p WHERE p.id = reviews.product_id AND p.merchant_id = auth.uid()) OR is_admin());

-- messages : merchant OR customer OR admin
CREATE POLICY messages_conversation ON messages
  USING (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin());

-- notifications : owner or admin
CREATE POLICY notifications_owner ON notifications
  USING (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin());

-- coupons : merchant owner or admin
CREATE POLICY coupons_owner ON coupons
  USING (merchant_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR is_admin());

-- favorites : merchant/customer owner or admin
CREATE POLICY favorites_owner ON favorites
  USING (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR customer_id = auth.uid() OR is_admin());

-- merchant_analytics : merchant owner or admin
CREATE POLICY analytics_owner ON merchant_analytics
  USING (merchant_id = auth.uid() OR is_admin())
  WITH CHECK (merchant_id = auth.uid() OR is_admin());

-- ============================================================
-- TRIGGERS : mise à jour automatique updated_at (appliquée aux tables avec updated_at)
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attacher le trigger aux tables pertinentes
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchants' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_merchants_updated_at BEFORE UPDATE ON merchants FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='customers' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='reviews' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_reviews_updated_at BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_messages_updated_at BEFORE UPDATE ON messages FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='notifications' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_notifications_updated_at BEFORE UPDATE ON notifications FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='coupons' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_coupons_updated_at BEFORE UPDATE ON coupons FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchant_analytics' AND column_name='updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_merchant_analytics_updated_at BEFORE UPDATE ON merchant_analytics FOR EACH ROW EXECUTE FUNCTION update_updated_at()';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TRIGGER : mise à jour stats client après commande payée
-- ============================================================
CREATE OR REPLACE FUNCTION update_customer_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status <> 'paid') THEN
    UPDATE customers
    SET
      total_orders = total_orders + 1,
      total_spent  = total_spent + NEW.total_mad,
      last_order_at = NOW()
    WHERE id = NEW.customer_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_paid_update_customer
  AFTER INSERT OR UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION update_customer_stats();

-- ============================================================
-- TRIGGER : décrémenter stock automatiquement à la commande
-- ============================================================
CREATE OR REPLACE FUNCTION decrement_stock_on_order()
RETURNS TRIGGER AS $$
DECLARE
  item JSONB;
BEGIN
  -- Parcourir chaque article du panier
  FOR item IN SELECT * FROM jsonb_array_elements(NEW.items)
  LOOP
    UPDATE products
    SET stock = GREATEST(stock - (item->>'qty')::INTEGER, 0)
    WHERE id = (item->>'product_id')::UUID
      AND stock >= (item->>'qty')::INTEGER;
  END LOOP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_decrement_stock
  AFTER INSERT ON orders
  FOR EACH ROW
  WHEN (NEW.status = 'paid')
  EXECUTE FUNCTION decrement_stock_on_order();

-- ============================================================
-- FONCTIONS UTILITAIRES
-- ============================================================
-- Retourne statistiques rapides pour un marchand
CREATE OR REPLACE FUNCTION get_merchant_stats(m_uuid UUID)
RETURNS TABLE(total_orders INTEGER, total_revenue NUMERIC, avg_order_value NUMERIC) LANGUAGE sql AS $$
  SELECT
    COUNT(*) FILTER (WHERE o.status = 'paid')::INT AS total_orders,
    COALESCE(SUM(o.total_mad) FILTER (WHERE o.status = 'paid'), 0)::NUMERIC AS total_revenue,
    CASE WHEN COUNT(*) FILTER (WHERE o.status = 'paid') = 0 THEN 0 ELSE (SUM(o.total_mad) FILTER (WHERE o.status = 'paid')/COUNT(*) FILTER (WHERE o.status = 'paid')) END::NUMERIC
  FROM orders o
  WHERE o.merchant_id = m_uuid;
$$;

-- Top products vendus pour un marchand
CREATE OR REPLACE FUNCTION get_top_products(m_uuid UUID, lim INTEGER DEFAULT 10)
RETURNS TABLE(product_id UUID, product_name TEXT, total_qty INTEGER, total_revenue NUMERIC) LANGUAGE sql AS $$
  SELECT p.id, p.name, SUM(oi.qty) as total_qty, SUM(oi.subtotal) as total_revenue
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  JOIN products p ON p.id = oi.product_id
  WHERE o.merchant_id = m_uuid AND o.status = 'paid'
  GROUP BY p.id, p.name
  ORDER BY total_qty DESC
  LIMIT lim;
$$;

-- Met à jour la note moyenne d'un marchand depuis les avis
CREATE OR REPLACE FUNCTION update_merchant_rating(m_uuid UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  avg_rating NUMERIC(3,2);
BEGIN
  SELECT AVG(r.rating) INTO avg_rating
  FROM reviews r
  JOIN products p ON p.id = r.product_id
  WHERE p.merchant_id = m_uuid;

  UPDATE merchants SET rating_avg = avg_rating WHERE id = m_uuid;
END;
$$;

-- ============================================================
-- VUES UTILITAIRES
-- ============================================================
-- Vue : ventes quotidiennes pour Chart.js
CREATE OR REPLACE VIEW view_daily_sales AS
SELECT
  merchant_id,
  DATE(created_at) AS sale_date,
  COUNT(*) FILTER (WHERE status IN ('paid','delivered')) AS order_count,
  COALESCE(SUM(total_mad) FILTER (WHERE status IN ('paid','delivered')),0) AS revenue_mad
FROM orders
GROUP BY merchant_id, DATE(created_at)
ORDER BY sale_date DESC;

-- Vue : top produits vendus
CREATE OR REPLACE VIEW view_top_products AS
SELECT
  p.id as product_id,
  p.name AS product_name,
  p.category,
  p.merchant_id,
  SUM(oi.qty) AS total_qty_sold,
  SUM(oi.subtotal) AS total_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.id
JOIN orders o ON o.id = oi.order_id
WHERE o.status = 'paid'
GROUP BY p.id, p.name, p.category, p.merchant_id
ORDER BY total_qty_sold DESC;

-- Vue : dashboard marchand (résumé)
CREATE OR REPLACE VIEW view_merchant_dashboard AS
SELECT
  m.id as merchant_id,
  m.shop_name,
  COALESCE(s.total_orders,0) as total_orders,
  COALESCE(s.total_revenue,0) as total_revenue,
  COALESCE(a.visits,0) as visits_today,
  m.rating_avg
FROM merchants m
LEFT JOIN (
  SELECT merchant_id, COUNT(*) as total_orders, SUM(total_mad) as total_revenue FROM orders WHERE status = 'paid' GROUP BY merchant_id
) s ON s.merchant_id = m.id
LEFT JOIN merchant_analytics a ON a.merchant_id = m.id AND a.date = CURRENT_DATE;

-- ============================================================
-- DONNÉES DE TEST (seed)
-- ============================================================
-- 3 marchands démo
INSERT INTO merchants (id, email, password_hash, shop_name, city, phone, locale)
VALUES
  ('11111111-0000-0000-0000-000000000001','amine@boutique.ma','pbkdf2:demo','Boutique Amine','Casablanca','+212600111111','fr'),
  ('22222222-0000-0000-0000-000000000002','souad@artisan.ma','pbkdf2:demo','Souad Artisanat','Rabat','+212600222222','fr'),
  ('33333333-0000-0000-0000-000000000003','karim@tech.ma','pbkdf2:demo','Karim Tech','Marrakech','+212600333333','fr')
ON CONFLICT DO NOTHING;

-- Produits exemples
INSERT INTO products (merchant_id, name, category, price_mad, stock, stock_alert, image_url, is_flash_sale, flash_price, sku)
VALUES
  ('11111111-0000-0000-0000-000000000001','Babouches Cuir Homme','mode',199.00,20,3,'https://via.placeholder.com/400x400?text=Babouches',FALSE,NULL,'BBO-001'),
  ('11111111-0000-0000-0000-000000000001','Thé à la menthe (250g)','deco',45.00,100,10,'https://via.placeholder.com/400x400?text=The',FALSE,NULL,'THE-250'),
  ('22222222-0000-0000-0000-000000000002','Tapis Kilim 120x180','deco',899.00,5,2,'https://via.placeholder.com/400x400?text=TapisKilim',FALSE,NULL,'TK-120'),
  ('33333333-0000-0000-0000-000000000003','Powerbank 10000mAh','tech',299.00,30,5,'https://via.placeholder.com/400x400?text=Powerbank',TRUE,249.00,'PB-10000')
ON CONFLICT DO NOTHING;

-- Customers demo
INSERT INTO customers (id, merchant_id, full_name, email, phone, city, total_orders, total_spent)
VALUES
  ('51111111-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','Fatima Zahra','fz@exemple.ma','+212661234567','Casablanca',2,399.00),
  ('52222222-0000-0000-0000-000000000002','22222222-0000-0000-0000-000000000002','Mohamed El','me@exemple.ma','+212677654321','Rabat',1,899.00)
ON CONFLICT DO NOTHING;

-- Exemple de commande payée
INSERT INTO orders (id, merchant_id, customer_id, items, total_mad, status, payment_method)
VALUES (
  '41111111-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', '51111111-0000-0000-0000-000000000001',
  '[{"product_id":"11111111-0000-0000-0000-000000000001","name":"Babouches Cuir Homme","price_mad":199.00,"qty":2}]'::jsonb,
  398.00, 'paid', 'cash'
)
ON CONFLICT DO NOTHING;

-- order_items correspondant
INSERT INTO order_items (order_id, product_id, name, price_mad, qty)
VALUES ('41111111-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','Babouches Cuir Homme',199.00,2)
ON CONFLICT DO NOTHING;

-- Exemple d'avis
INSERT INTO reviews (product_id, buyer_id, rating, comment)
VALUES ('11111111-0000-0000-0000-000000000001','51111111-0000-0000-0000-000000000001',5,'Excellent produit, très confortable')
ON CONFLICT DO NOTHING;

-- Coupon demo
INSERT INTO coupons (merchant_id, code, percent_off, starts_at, ends_at, max_uses)
VALUES ('11111111-0000-0000-0000-000000000001','WELCOME10',10.0, NOW(), NOW() + INTERVAL '30 days', 100)
ON CONFLICT DO NOTHING;

-- Favorites demo
INSERT INTO favorites (merchant_id, customer_id, product_id)
VALUES ('11111111-0000-0000-0000-000000000001','51111111-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- ============================================================
-- FIN DU SCHEMA AMÉLIORÉ
-- ============================================================
