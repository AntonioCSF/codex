<apply template="_base">
<h1>Acesso não autorizado!</h1>
<ul>
<li>Não tem autorização para visualizar esta página;
  por favor retroceda à página anterior.</li>
<ifLoggedOut>
  <li>Se a sua sessão expirou por inatividade
    tente <a href="/login">autenticar-se novamente.</a></li>
</ifLoggedOut>
</ul>
</apply>
