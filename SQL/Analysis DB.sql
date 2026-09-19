-- Анализ базы данных --

-- Определяем какая доля доставленных заказов была доставлена с опозданием, а какая — вовремя или раньше.
select count (distinct order_id) filter (where order_status = 'delivered') as total_orders,
	sum(case when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) = date_trunc('day',order_delivered_customer_date) then 1 else 0 end) as order_in_time,
	round((sum(case when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) = date_trunc('day',order_delivered_customer_date) then 1 else 0 end)::numeric /(count (distinct order_id) filter (where order_status = 'delivered'))::numeric) *100, 2)  as percent_in_time,
	sum(case when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date) then 1 else 0 end) as order_slow,
	round((sum(case when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date) then 1 else 0 end)::numeric /(count (distinct order_id) filter (where order_status = 'delivered'))::numeric) *100, 2)  as percent_slow,
	sum(case when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) > date_trunc('day',order_delivered_customer_date) then 1 else 0 end) as order_fast,
	round((sum(case when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) > date_trunc('day',order_delivered_customer_date) then 1 else 0 end)::numeric /(count (distinct order_id) filter (where order_status = 'delivered'))::numeric) *100, 2)  as percent_fast
from orders

-- Задержка заказов происходит почти с 7% случаев. Таким образом нужно выяснить на сколько именно дней задерживается доставка.
select
	min(order_delivered_customer_date::date - order_estimated_delivery_date::date) as min_wait,
	max(order_delivered_customer_date::date - order_estimated_delivery_date::date) as max_wait,
	round(avg(order_delivered_customer_date::date - order_estimated_delivery_date::date),0) as avg_wait
from orders
where order_status = 'delivered'
	and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date)

-- Максимальное время ожидания заказа составляет 188 лней, что скорее всего является выбросом и будет проанализировано далее (поиск медианы). Среднее опоздание ~ 11 дней.
select percentile_cont(0.5) 
within group (order by order_delivered_customer_date::date - order_estimated_delivery_date::date) as median_wait
from orders
where order_status = 'delivered'
	and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date)

-- Медианное значение составляет 7 дней, что говорит о выбросах в данных. Найду топ-50 заказов по ожиданию:
select order_id,
	order_delivered_customer_date::date - order_estimated_delivery_date::date as delay_days
from orders
where order_status = 'delivered'
	and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date)
order by delay_days desc
limit 50

-- Выяснилось, что длительные задержки случаются достаточно часто. Случаев задержки больше 30 дней - 345.
select count(*) filter (where order_delivered_customer_date::date - order_estimated_delivery_date::date > 30) as delay_more_30_days,
	count(*) filter (where order_delivered_customer_date::date - order_estimated_delivery_date::date > 60) as delay_more_60_days,
	count(*) filter (where order_delivered_customer_date::date - order_estimated_delivery_date::date > 90) as delay_more_90_days,
	count(*) filter (where order_delivered_customer_date::date - order_estimated_delivery_date::date > 120) as delay_more_120_days,
	count(*) filter (where order_delivered_customer_date::date - order_estimated_delivery_date::date > 150) as delay_more_150_days
from orders
where order_status = 'delivered'
	and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date)

-- Необходимо найти идентификатор заказов с задержкой больше 30 дней и продавцов - "системных нарушителей" доставки
with delay_order_id as(
	select order_id from orders 
	where order_status = 'delivered' and order_delivered_customer_date::date - order_estimated_delivery_date::date > 30)

select oi.seller_id, count (distinct oi.order_id) as count_orders
from order_items oi
join delay_order_id doi on oi.order_id = doi.order_id
group by oi.seller_id
having count(distinct oi.order_id) >1
order by count_orders desc


--Сравню средний рейтинг отзыва между тремя группами доставленных заказов: теми, что были доставлены с опозданием, и теми, что были доставлены вовремя и раньше. 
select 
	round(avg(case when o.order_status = 'delivered' and date_trunc('day', o.order_estimated_delivery_date) = date_trunc('day', o.order_delivered_customer_date) then orre.review_score else null end),2) as review_in_time,
	round(avg(case when o.order_status = 'delivered' and date_trunc('day', o.order_estimated_delivery_date) < date_trunc('day', o.order_delivered_customer_date) then orre.review_score else null end),2) as review_slow,
	round(avg(case when o.order_status = 'delivered' and date_trunc('day', o.order_estimated_delivery_date) > date_trunc('day', o.order_delivered_customer_date) then orre.review_score else null end),2) as review_fast
from order_reviews orre
join orders o on orre.order_id = o.order_id


--Разделю опоздавшие заказы на группы по величине задержки: 1-7 дней, 8-14 дней, 15-30 дней, больше 30 дней — и посчитаю средний рейтинг отзыва.
select 
	round(avg(orre.review_score) filter (where o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date between 1 and 7),2) as review_1_weak,
	round(avg(orre.review_score) filter (where o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date between 8 and 14),2) as review_2_weak,
	round(avg(orre.review_score) filter (where o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date between 15 and 30),2) as review_2_weak_to_month,
	round(avg(orre.review_score) filter (where o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date > 30),2) as review_more_weak
from order_reviews orre
join orders o on orre.order_id = o.order_id
where o.order_status = 'delivered'
	and date_trunc('day', o.order_estimated_delivery_date) < date_trunc('day', o.order_delivered_customer_date)


-- Следующий логичный срез — география: определю топ-10 штатов по среднему опозданию в днях среди всех доставленных заказов этого штата.
select c.customer_state,
	round(avg(order_delivered_customer_date::date - order_estimated_delivery_date::date),0) as avg_wait
from customers c
join orders o on c.customer_id = o.customer_id
where order_status = 'delivered'
group by c.customer_state
order by avg_wait desc
limit 10

-- Посчитаю для каждого штата долю опозданий и выявлю 10 "лидеров"
select c.customer_state,
	count (case when o.order_status = 'delivered' then 1 end) as count_ordrers,
	round(avg(case when o.order_status = 'delivered' and date_trunc('day', o.order_estimated_delivery_date) < date_trunc('day', o.order_delivered_customer_date) then  o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date else null end),0) as avg_slow_day,
	
	round(count(case when o.order_status = 'delivered' and date_trunc('day', o.order_estimated_delivery_date)::date < date_trunc('day', o.order_delivered_customer_date)::date then 1 end)::numeric / 
	count (case when o.order_status = 'delivered' then 1 end)::numeric * 100, 1) as percent_slow
	
from customers c 
join orders o on c.customer_id = o.customer_id
group by c.customer_state
order by percent_slow desc
limit 10

-- Найду количество заказов по каждому уникальному клиенту и было ли опоздание хоть одного заказа (0 - не было, 1 - было)
with was_delay_customer as (
select c.customer_unique_id, count(o.customer_id) as total_order,
	max(case when o.order_status = 'delivered' and date_trunc('day', o.order_estimated_delivery_date) < date_trunc('day', o.order_delivered_customer_date) then 1 else 0 end) as was_delay
from customers c
join orders o on c.customer_id = o.customer_id
group by c.customer_unique_id
order by total_order desc)

select was_delay, count (*) as total_customer,
	count (*) filter (where total_order >1 ) as total_retention,
	round((count (*) filter (where total_order >1)::numeric / count (*)::numeric * 100),2) as percent_retention
	
from was_delay_customer
group by was_delay
-- Данный анализ показывает, что при отсутствии задержки возвращение клиента примерно 3%, а при задержке - почти 5%, что в корне не может быть верно.
-- Чтобы получить правдоподные данные я найду по каждому клиенту его первый заказ, который опоздал и вернулся ли клиент после этого.

with first_order_ranked as(
	select c.customer_unique_id, o.order_purchase_timestamp::date as first_order,
	case 
	when order_status = 'delivered' and date_trunc('day', order_estimated_delivery_date) < date_trunc('day',order_delivered_customer_date) then 1 
	else 0 end as first_order_was_late,
	row_number() over (partition by c.customer_unique_id order by o.order_purchase_timestamp) as rn
from orders o
join customers c on o.customer_id = c.customer_id),

customer_order_counts as(
	select c.customer_unique_id, count(o.order_id) as total_orders
from customers c
join orders o on c.customer_id = o.customer_id
group by c.customer_unique_id)

select f.first_order_was_late,
	count (*) as total_customers,
	count (*) filter (where c.total_orders > 1) as returned_customers,
	round(100.0 * count(*) filter (where c.total_orders > 1) / count(*), 2) as retention_percent
from first_order_ranked f
join customer_order_counts c on f.customer_unique_id = c.customer_unique_id
where rn = 1
group by f.first_order_was_late






































--
select count(distinct customer_unique_id) as total_unique_customer,
	count(distinct customer_unique_id) 
from customers c
join orders o on c.customer_id = o.customer_id

