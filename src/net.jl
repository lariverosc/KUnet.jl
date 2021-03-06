function backprop(net::Net, x, dy, loss=softmaxloss)
    y = forw(net, x) 	# y: network output
    loss(y, dy)         # dy: desired output -> gradient
    back(net, dy)       # calculate derivatives
end

function forw(l::Layer, x, apply_fx=true)
    initforw(l, x)
    isdefined(l,:fx) && apply_fx && l.fx(l,x)
    @into! l.y = l.w * x
    isdefined(l,:b) && (@in1! l.y .+ l.b)
    isdefined(l,:f) && l.f(l,l.y)
    l.x = x
    return l.y
end

function back(l::Layer, dy, return_dx=true)
    initback(l, dy, return_dx)
    isdefined(l,:f) && l.f(l,l.y,dy)
    @into! l.dw = dy * l.x'
    isdefined(l,:b) && sum!(l.db, dy)
    return_dx || return
    @into! l.dx = l.w' * dy
    isdefined(l,:fx) && l.fx(l,l.x,l.dx)
    return l.dx
end

initforw(l, x)=chksize(l, :y, l.w, (size(l.w,1),size(x,2)))
initback(l, dy, return_dx)=(chksize(l, :dw, l.w); chksize(l, :db, l.b); return_dx && chksize(l, :dx, l.x))
forw(n::Net, x, fx=true) = (for l=n x=forw(l,x,fx) end; x)
back(n::Net, dy) = (for i=length(n):-1:1 dy=back(n[i],dy,i>1) end)


function train(net::Net, x, y; batch=128, iters=0, loss=softmaxloss)
    buf = inittrain(net, x, y, batch)
    xrows,xcols = size(x)
    yrows,ycols = size(y)
    for b = 1:batch:xcols
        e = b + batch - 1
        if (e > xcols)
            e = xcols
            chksize(buf, :x, net[1].w, (xrows, e-b+1))
            chksize(buf, :y, net[end].w, (yrows, e-b+1))
        end
        copy!(buf.x, (1:xrows,1:e-b+1), x, (1:xrows,b:e))
        copy!(buf.y, (1:yrows,1:e-b+1), y, (1:yrows,b:e))
        backprop(net, buf.x, buf.y, loss)
        for l in net
            isdefined(l,:w) && update(l.w, l.dw, l.pw)
            isdefined(l,:b) && update(l.b, l.db, l.pb)
        end
        iters > 0 && e/batch >= iters && break
    end
    free(buf.x); free(buf.y) # this should not be necessary now that gc() works...
end

function inittrain(net::Net, x, y, batch)
    for l in net
        isdefined(l,:w) && !isdefined(l,:pw) && (l.pw = UpdateParam())    
        isdefined(l,:b) && !isdefined(l,:pb) && (l.pb = UpdateParam())
    end
    buf = XY()
    chksize(buf, :x, net[1].w, (size(x, 1), batch))
    chksize(buf, :y, net[end].w, (size(y, 1), batch))
    return buf
end

function predict(net::Net, x; batch=0)
    xrows,xcols = size(x)
    yrows,ycols = size(net[end].w, 1), xcols
    y = similar(x, (yrows, ycols))
    (batch == 0) && (batch = xcols)
    xx = similar(net[1].w, (xrows, batch))
    for b = 1:batch:xcols
        e = b + batch - 1
        if (e > xcols || b == 1)
            (e > xcols) && (e = xcols)
            free(xx)
            xx = similar(net[1].w, (xrows, e-b+1))
        end
        yy = copy!(xx, (1:xrows,1:e-b+1), x, (1:xrows,b:e))
        yy = forw(net, yy, false)
        copy!(y, (1:yrows,b:e), yy, (1:yrows,1:e-b+1))
    end
    free(xx)
    return y
end


function chksize(l, n, a, dims=size(a); fill=nothing)
    if !isdefined(l,n) 
        l.(n) = similar(a, dims)
        fill != nothing && fill!(l.(n), fill)
    elseif size(l.(n)) != dims
        free(l.(n))
        l.(n) = similar(a, dims)
        fill != nothing && fill!(l.(n), fill)
    end
end

