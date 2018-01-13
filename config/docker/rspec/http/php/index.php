<?php

// this file handles uploading of transcoded media

foreach($_FILES as $k => $f) {
  error_log($k . ' ' . print_r($f, 1));
  $file_name = empty($_REQUEST['key']) ? $f['name'] : $_REQUEST['key'];
  move_uploaded_file($f['tmp_name'], '/var/www/html/posts/' . $file_name);
}
