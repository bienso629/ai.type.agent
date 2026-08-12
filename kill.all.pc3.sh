#!/bin/bash
pm2 stop all
pm2 delete all
pm2 kill
pm2 delete tab1-chatbot tab2-cdn tab3-n8n tab6-nodebb tab7-cloudflared tab9-apiv3 2>/dev/null