#Future Chapter 5 Below

##Plotting with `ni --js`
Check out the [tutorial](tutorial.md) for some examples of cool, interactive `ni` plotting.

**TODO**: Say something useful.


##Custom Compound Reduce
#### `rfn`: Custom compound reduce

**TODO: Understand this**

##Partitioned Matrix Operations

Operations on huge matrices are not entirely `ni`ic, since they may require space greater than memory, whichwill make them slow. However, operators are provided to improve These operations are suited best to 


* `X<col>`, `Y<col>`, `N<col>`: Matrix Partitioning
  * **TODO**: understand how these actually work.
* `X`: sparse-to-dense transformation
  * In the case that there are collisions for locations `X`, `X` will sum the values
  * For example: `ni n010p'r 0, a%3, 1' X`

##Disk-Backed Data Closures

* `@:[disk_backed_data_closure]`

##Binary Operations
In theory, this can save you a lot of space. But I haven't used this in practice.

##Less Useful `ni`-specific Perl Extensions


###Array Functions
  * `clip`
  * `within`
  

   
##Writing Your Own `ni` Extensions
**TODO** Understand how this works

##Obscure Interops/Extensions

* [SQL](sql.md)
* [PySpark](pyspark.md)
* [Scripting](script.md)
* [HTTP Operations](net.md)
* [Defining `ni` functions](fn.md)