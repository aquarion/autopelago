<?PHP
# {{ ansible_managed }}

$purl = parse_url($_SERVER['REQUEST_URI']);

if ($purl['path'] == '/favicon.ico'){
	header("Content-Type: image/x-icon");
	readfile("page.ico");
	die();
}

$host = $_SERVER['HTTP_HOST'];

$error = "File not Found";


if (
	file_exists("/var/www/hosts/vault/".$host)
	|| file_exists("/var/www/hosts/vault/".$host.'.zip')
	|| file_exists("/var/www/hosts/gone/".$host)
){
	header("HTTP/1.1 410 Gone");
	include("410.html");
	die();
}


if (!file_exists("/var/www/hosts/".$host)){

	$error = "Host not configured";

	if(file_exists("/var/www/hosts/www.".$host)){
		header("location: http://www.".$host.$_SERVER['REQUEST_URI']);
		die("No host, but there is a www version of it");
	}

	if(preg_match("#^www\.#", $host) && file_exists("/var/www/hosts/".substr($host, 4))){
		header("location: http://".substr($host,4).$_SERVER['REQUEST_URI']);
		die("No host, but there is a non-www version of it");
	}

	$bom = explode(".", $host);

	if (substr($host,-5) == "co.uk"){
		$check = implode(".",array_slice($bom, 0,-2));
	} else {
		$check = implode(".",array_slice($bom, 0,-1));
	}
	$glob = glob("/var/www/hosts/".$check.".*");

	if(count($glob) > 1){
		$try = $glob;
	} elseif(count($glob)){
		header("location: http://".basename($glob[0]));
		die("Found you");
	}


	$check = implode(".",array_slice($bom, 0, 1));
	$glob = glob("/var/www/hosts/www.".$check.".*");
	if(count($glob) > 1){
		$try = $glob;
	} elseif(count($glob)){
		header("location: http://".basename($glob[0]));
		die("Found you");
	}

	$check = implode(".",array_slice($bom, 0, 1));
	$glob = glob("/var/www/hosts/*.".$check.".*");
	if(count($glob) > 1){
		$try = $glob;
	} elseif(count($glob)){
		header("location: http://".basename($glob[0]));
		die("Found you");
	}
	header("HTTP/1.1 404 File Not Found");
	include("404_host.html");
	die();

}

header("HTTP/1.1 404 File Not Found");
include("404.html");
