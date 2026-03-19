{{- SET msg = task.settings.message || '' -}}
{{- SET msg_html = msg.replace("\n", "<br>") -}}
{{- SET html_body = '<html><body style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background-color:#f5f5f5;margin:0;padding:20px"><div style="max-width:600px;margin:0 auto;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08)"><div style="background:linear-gradient(135deg,#6366f1,#8b5cf6);padding:32px;text-align:center"><h1 style="color:#ffffff;margin:0;font-size:24px;font-weight:600">HQ VPN</h1></div><div style="padding:32px"><div style="font-size:16px;line-height:1.6;color:#333333">' _ msg_html _ '</div></div><div style="padding:24px 32px;background:#f9fafb;text-align:center;font-size:13px;color:#9ca3af">HQ VPN - Secure and Fast</div></div></body></html>' -}}
{{- SET to_email = task.settings.to || user(task.user_id).settings.email -}}
{{- SET body = { sender = { name = "HQ VPN", email = "noreply@z-hq.com" }, to = [{ email = to_email }], subject = task.settings.subject, htmlContent = html_body } -}}
{{- toJson(body) -}}
