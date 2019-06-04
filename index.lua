local version_str = string.format("%s (%s; %s; %s)", _VERSION, jit.os, jit.arch, jit.version)

print([[
<html>
<head><title>Hello world!</title></head>
<body>
<center><h1>Hello world!</h1></center>
<hr><center>$version_str</center>
</body>
</html>
]])