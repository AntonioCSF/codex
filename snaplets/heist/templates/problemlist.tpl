<apply template="base">
<h1>Problemas</h1>
<div class="filterlist">
<form action="/problems" method="get">
<dl>
<dt>Filtrar problemas:</dt>
<dt class="info">(<visibleProblems/> de <totalProblems/> vísiveis)</dt>
<tagList>
<dt><tagCheckbox/></dt>
</tagList>
</dl>
<p><input type="submit" value="Aplicar"/></p>
<p><a href="/problems">Limpar filtros</a></p>
</form>
</div>

<div class="problemlist">
<dl>
<problemList>
  <dt><a href="/problems/${probID}"><probTitle/></a><ifAccepted><img src="/icons/16x16/accepted.png" alt="Accepted"/></ifAccepted></dt>
    <dd class="problemli"><span class="info">
	<ifSubmitted><count/> submissões já efetuadas.<br/></ifSubmitted>
	<ifOpen>
	<ifLimited>
	  Submissões terminam em <probEnd/>; tempo disponível: <em><probTimeLeft/></em>.
	</ifLimited>
	<else>
	<ifEarly>Submissões iniciam em <probStart/>.</ifEarly>
	<ifLate>Submissões fecharam em <probEnd/>.</ifLate>
	</else>
	</ifOpen>
    </span></dd>
</problemList>
</dl>
</div>

</apply>
