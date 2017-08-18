# rspamd-elastic
Metadata collector for rspamd using elasticsearch backend

### Demo
<a target="_blank" href="https://github.com/Menta2L/rspamd-elastic/"><img src="http://i.imgur.com/etYWT8R.png" width="600" /></a>

## Requierment
- [Rspamd](https://rspamd.com) - Advanced antispam engine
- [Elasticsearch 5.5](https://www.elastic.co/) - Indexing database
- [ingest-geoip](https://www.elastic.co/guide/en/elasticsearch/plugins/master/ingest-geoip.html) - Elasticsearch plugin used for geoip resolve
- [Kibana](https://www.elastic.co/products/kibana) (optional) - Used for data visualization

## Todo
 - Better error handling. Make a strategy what to do if elasticsearch fails to create document or index
 - Import predefined dashboard and visualizations into kibana index.
 - Some optimizations on mapping template
