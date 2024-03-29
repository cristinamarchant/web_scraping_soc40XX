# title: "Lecturas de sitios web"
# subtitle: "Web Scraping y acceso a datos desde la web con R"
# author: Cristián Ayala
# date: 2022-06-02

suppressPackageStartupMessages(library(tidyverse))
library(rvest)

# Ejemplo 1: Biblioteca ----
# 
# Valores promedio por categoría

url <- 'http://books.toscrape.com/'

## Web main ----
html_main <- read_html(paste0(url, 'index.html'))

## data.frame con categorías ----
l_cat <- html_main |> html_elements('ul.nav ul a')

df_cat <- tibble(categoria = l_cat |> html_text(),
                 link      = l_cat |> html_attr('href')) |> 
  mutate(categoria = stringr::str_squish(categoria))

# Lectura de página web inicial de cada categoría 
df_cat <- df_cat |> 
  rowwise() |> 
  mutate(pagina = list(read_html(paste0(url, link))))

# Obtención de datos para construir links

html_main |>  html_elements('li.current') |> 
  html_text() |> 
  str_extract('(?<= of )\\d{1,2}')

f_n_paginas <- function(.html){
  # Función para obtener el número de páginas.
  x <- .html |> 
    html_elements('li.current') |> 
    html_text() |> 
    str_extract('(?<= of )\\d{1,2}')
  
  if(identical(x, character(0))) {
    x <- "0"
  }
  as.integer(x)
}

df_cat <- df_cat |> 
  mutate(libros_n  = html_elements(pagina, '.form-horizontal strong:first-of-type') |> html_text(),
         paginas_n = f_n_paginas(pagina))

# Construcción de links de páginas
# 
# Los links tienen la siguiente forma:
# http://books.toscrape.com/catalogue/category/books/mystery_3/page-1.html

f_make_page <- function(.n){
  # contrucción de vector de page-# según el número capturado.
  text <- 'index.html'
  
  # Crea link para página si hay más de 1
  if(.n > 0){
    text <- paste0(rep('page-', .n), seq_len(.n), '.html')
    text[1] <- 'index.html'
  }
  text
}

# Ejemplo:
f_make_page(0)
f_make_page(3)

df_cat <- df_cat |> 
  mutate(paginas_link = list(f_make_page(paginas_n)))

head(df_cat, 3)

# Agregar el root del link para cada página

df_cat <- df_cat |> 
  ungroup() |> 
  mutate(link = str_remove(link, 'index.html$')) |> 
  rowwise() |> 
  mutate(paginas_link = list(paste0(link, paginas_link)))

df_cat_hojas <- df_cat |> 
  unnest_longer(paginas_link)

head(df_cat_hojas, 3)

# Dividir base para evitar duplicar trabajo

df_cat_hojas <- df_cat_hojas |> 
  mutate(ya_leido = str_detect(paginas_link, 'index.html$'))

df_cat_hojas_ya_leidas <- df_cat_hojas |> 
  filter(ya_leido)

df_cat_hojas_por_leer <- df_cat_hojas |> 
  filter(!ya_leido)

df_cat_hojas_por_leer <- df_cat_hojas_por_leer |> 
  rowwise() |> 
  mutate(pagina = list(read_html(paste0(url, paginas_link))))


df_cat_hojas_leido <- bind_rows(df_cat_hojas_ya_leidas,
                                df_cat_hojas_por_leer) |> 
  select(categoria, libros_n, pagina)

# Nombre de los libros
df_cat_hojas_leido$pagina[[1]] |> html_elements('h3 a')
# Precio
df_cat_hojas_leido$pagina[[1]] |> html_elements('.price_color') |> html_text()

f_datos_libros <- function(.html){
  tibble(libro_name  = .html |> html_elements('h3 a') |> html_attr('title'),
         libro_price = .html |> html_elements('.price_color') |> html_text(),
         libro_url   = .html |> html_elements('h3 a') |> html_attr('href'))
}

df_cat_hojas_leido$pagina[[1]] |> f_datos_libros()

df_cat_hojas_leido <- df_cat_hojas_leido |> 
  rowwise() |> 
  mutate(libros = list(f_datos_libros(pagina)))

head(df_cat_hojas_leido, 3)

df_cat_hojas_leido <- df_cat_hojas_leido |> 
  unnest(libros)

head(df_cat_hojas_leido, 3)

df_cat_hojas_leido <- df_cat_hojas_leido |> 
  mutate(libro_price = str_remove(libro_price, '£'),
         libro_price = as.double(libro_price))


## Resultado ----

df_cat_hojas_leido |> 
  group_by(categoria) |> 
  summarise(libros_n = n(),
            libros_price = mean(libro_price))


# Ejemplo 2: Hockey Teams ----

url <- 'https://www.scrapethissite.com'

## Formulario ----
# 
# Usaremos el formulario para hacer búsqueda de los equipos de New York
s_main <- session(url)

s_main <- s_main |> 
  session_jump_to(url = 'pages/forms')

f_search <- html_form(s_main)
f_search <- f_search[[1]] # Pueden haber más de un formulario.


### html Buscamos por New York y obtenemos el html de respuesta. ----
f_search <- f_search |> 
  html_form_set(q = "New York")

resp <- html_form_submit(f_search)

# Primera página de respuestas
page_1 <- read_html(resp) |> 
  html_table()

page_1

### session Buscamos por New York y modificamos la sesión de respuesta. ----
s_resp <- session_submit(s_main,
                         form = f_search)

df_page_1s <- read_html(s_resp) |> 
  html_element('table') |> 
  html_table()

# Primera pagina capturada
df_page_1s

# Obtengamos los links restantes:
links_pagination <- s_resp$response |> 
  httr::content() |> # Extrae el contenido de una sesión.
  html_elements('.pagination a') |> 
  html_attr('href')

# Dejo solo los links de interés: elimino el 1º y el último.
links_pagination <- links_pagination[c(-1, -length(links_pagination))]

# Leo todos los links y luego obtengo una tabla.
page_restantes <- URLencode(links_pagination) |> 
  map(~s_resp |> session_jump_to(url = .))

df_page_2s <- page_restantes |> 
  map_df(~read_html(.) |> html_table())

df_page_2s

# Tabla completa

bind_rows(df_page_1s,
          df_page_2s)


### Creación de links si se conoce su formato ----

page_2 <- s_resp |> 
  session_jump_to('?page_num=2&q=New%20York')

page_2 |> 
  read_html() |> 
  html_table()


## Analizando la url de búsqueda ----
# 
# 'https://www.scrapethissite.com/pages/forms/?page_num=1&per_page=25&q=New%20York'

url <- 'https://www.scrapethissite.com/pages/forms/?per_page=100&q=New%20York'

resp <- read_html(url)

resp |> 
  html_table()


# Obteniendo todos los datos

url <- 'https://www.scrapethissite.com/pages/forms/?per_page=1000'

resp <- read_html(url)

resp |> 
  html_table()


# Ejemplo 3: Oscar Winning Films: AJAX and Javascript ----
# 
# En la página se tiene que ver la petición de datos para obtener la información.

url <- 'https://www.scrapethissite.com/pages/ajax-javascript/'

read_html(url) |> 
  html_element('body')

# Cuando se actualizan los años, esta es la dirección utilizada
url_ajax <- 'https://www.scrapethissite.com/pages/ajax-javascript'


# Año 2010
jsonlite::fromJSON(paste0(url_ajax, '?ajax=true&year=2010'))

# Lectura de todos los años

anios <- 2010:2015
url_anios <- paste0(url_ajax, '?ajax=true&year=', anios)


df_ajax <- map_dfr(url_anios,
                   jsonlite::fromJSON)

df_ajax

# Se puede crear una sesión usando httr:

s_ajax <- httr::GET(url_ajax,
                    query = list(ajax = 'true', year = 2010))

s_ajax


# Ejemplo 4: SPD ----
# 
# Listado de estudios y archivos

url <- 'http://cead.spd.gov.cl/centro-de-documentacion/'

html <- read_html(url)

html |> 
  html_elements('body')

url_tabla <- 'http://cead.spd.gov.cl/wp-content/plugins/download-manager/tpls/query.php?length=-1&selectTotal=-1'

spd_proj <- jsonlite::fromJSON(url_tabla)

spd_proj |> class()

df_spd_proj <- spd_proj |> 
  as_tibble()

# La columna aaData es una matriz
head(df_spd_proj)

head(df_spd_proj$aaData, 2)

# De matriz a data.frame y luego unpack
df_spd_proj <- df_spd_proj |> 
  mutate(aaData = as.data.frame(aaData)) |> 
  unpack(aaData)

head(df_spd_proj)


# Links para descargar archivos. Probemos con el 1er caso
df_spd_proj$V5[[1]] |> 
  xml2::as_xml_document() |> 
  html_element('a') |>
  html_attr('href')

f_links_spd <- function(.chr){
  # Función para obtener el link de descarga de cada archivo.
  xml2::as_xml_document(.chr) |> 
    html_element('a') |>
    html_attr('href')
}

df_spd_proj <- df_spd_proj |> 
  rowwise() |> 
  mutate(link = f_links_spd(V5),
         .before = V5) |> 
  ungroup()

df_spd_proj <- df_spd_proj |> 
  mutate(link_full = paste0('http://cead.spd.gov.cl', link),
         .after = link)

### Bajar archivos ----
# Prueba con un link
file <- httr::GET(url = df_spd_proj$link_full[[1]])

# Obtener el nombre del archivo desde el header del requerimiento.
file_name <- httr::headers(file)$`content-disposition` |> 
  str_extract('(?<=\").*(?=\")')

writeBin(httr::content(file),
         con = file.path('slides/class_4/class_4_taller_download/', file_name))


# Usaremos solo 3 archivos para no bajar demasiada información

f_get_file_name <- function(x){
  httr::headers(x)$`content-disposition` |> 
    str_extract('(?<=\").*(?=\")')
}

df_spd_proj_test <- df_spd_proj |> 
  slice(1:3) |> 
  rowwise() |> 
  mutate(file = list(httr::GET(url = link_full)),
         file_name = f_get_file_name(file),
         .after = V1)

walk2(df_spd_proj_test$file,
      df_spd_proj_test$file_name,
      ~writeBin(httr::content(.x),
               con = file.path('slides/class_4/class_4_taller_download/', .y)))
