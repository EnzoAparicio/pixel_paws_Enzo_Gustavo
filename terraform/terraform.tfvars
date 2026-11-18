equipo = "aparicio-gonzalez"
owner  = "enzo-aparicio"

# repositorio_github y emails_alerta NO van aca: el repo es publico y los mails son
# datos personales. Entran por variables de entorno:
#   GitHub Actions: TF_VAR_repositorio_github sale solo de github.repository, y
#                   TF_VAR_emails_alerta del secret EMAILS_ALERTA.
#   Local:          export TF_VAR_repositorio_github="owner/repo"
#                   export TF_VAR_emails_alerta='["mail1@x.com","mail2@y.com"]'

# La organizacion que administra la cuenta bloquea los proveedores OIDC (SCP).
# El codigo queda escrito: se muestra con terraform plan -var enable_oidc=true
enable_oidc = false
